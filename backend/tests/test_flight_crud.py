"""Contratos publicos de edicion y eliminacion segura de vuelos."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from datetime import datetime, timedelta, timezone

import pytest

from backend.tests.test_api import api, auth, token_para


def vuelo_valido(**cambios):
    return {"origen": "Quito, Ecuador", "destino": "Cuenca, Ecuador",
            "fecha": (datetime.now(timezone(timedelta(hours=-5))).date() + timedelta(days=3)).isoformat(),
            "hora_salida": "10:00", "hora_llegada": "11:00", "precio": 10,
            "asientos_disponibles": 3, **cambios}


def preparar(api):
    cliente, repo = api
    token = token_para(cliente)
    repo.users["ana@example.com"]["rol"] = "ADMIN"
    respuesta = cliente.post("/api/vuelos", json=vuelo_valido(), headers=auth(token))
    assert respuesta.status_code == 201
    return cliente, repo, token, next(v for v in repo.flights if v["id"] == respuesta.json["vuelo"]["id"])


def test_editar_y_eliminar_preserva_historial_y_oculta_vuelo(api):
    cliente, repo, token, vuelo = preparar(api)
    assert vuelo["version"] == 1 and vuelo["activo"] is True
    editado = cliente.put(f"/api/vuelos/{vuelo['id']}", headers=auth(token),
                         json={**vuelo_valido(precio=12, asientos_disponibles=0), "version": vuelo["version"]})
    assert editado.status_code == 200
    actual = editado.json["vuelo"]
    assert actual["version"] == 2 and actual["asientos_disponibles"] == 0
    eliminado = cliente.delete(f"/api/vuelos/{vuelo['id']}", headers=auth(token), json={"version": 2})
    assert eliminado.status_code == 200
    assert all(v["id"] != vuelo["id"] for v in cliente.get("/api/vuelos").json)
    guardado = next(v for v in repo.flights if v["id"] == vuelo["id"])
    assert guardado["activo"] is False and guardado["version"] == 3
    reserva = cliente.post("/api/reservas", headers=auth(token), json={"vuelo_id": vuelo["id"], "cantidad": 1})
    assert reserva.status_code == 404
    assert not repo.reservations


@pytest.mark.parametrize("metodo", ["put", "delete"])
def test_mutaciones_solo_admin_y_version_obligatoria(api, metodo):
    cliente, repo, token, vuelo = preparar(api)
    ruta = f"/api/vuelos/{vuelo['id']}"
    cuerpo = {**vuelo_valido(), "version": 1}
    assert getattr(cliente, metodo)(ruta, json=cuerpo).status_code == 401
    usuario = token_para(cliente, "beto@example.com")
    assert getattr(cliente, metodo)(ruta, json=cuerpo, headers=auth(usuario)).status_code == 403
    assert vuelo["version"] == 1
    for version in [None, True, 1.5, "1", 0, -1, 2147483648]:
        respuesta = getattr(cliente, metodo)(ruta, json={**cuerpo, "version": version}, headers=auth(token))
        assert respuesta.status_code == 400
        assert vuelo["version"] == 1


def test_version_obsoleta_no_sobrescribe_ni_borra(api):
    cliente, repo, token, vuelo = preparar(api)
    ruta = f"/api/vuelos/{vuelo['id']}"
    assert cliente.put(ruta, headers=auth(token), json={**vuelo_valido(precio=20), "version": 1}).status_code == 200
    for metodo in ["put", "delete"]:
        conflicto = getattr(cliente, metodo)(ruta, headers=auth(token), json={**vuelo_valido(precio=99), "version": 1})
        assert conflicto.status_code == 409
        assert conflicto.json["error"]["codigo"] == "vuelo_modificado"
    assert vuelo["precio"] == 20 and vuelo["activo"] is True


def test_reservar_y_cancelar_invalidan_editor_y_borrado_con_reservas_se_bloquea(api):
    cliente, repo, token, vuelo = preparar(api)
    ruta = f"/api/vuelos/{vuelo['id']}"
    reserva = cliente.post("/api/reservas", headers=auth(token), json={"vuelo_id": vuelo["id"], "cantidad": 2})
    assert reserva.status_code == 201
    assert vuelo["version"] == 2 and vuelo["asientos_disponibles"] == 1
    for metodo in ["put", "delete"]:
        conflicto = getattr(cliente, metodo)(ruta, headers=auth(token), json={**vuelo_valido(), "version": 1})
        assert conflicto.status_code == 409 and conflicto.json["error"]["codigo"] == "vuelo_modificado"
    bloqueado = cliente.delete(ruta, headers=auth(token), json={"version": 2})
    assert bloqueado.status_code == 409 and bloqueado.json["error"]["codigo"] == "vuelo_con_reservas"
    importe = repo.reservations[reserva.json["reserva_id"]]["total"]
    assert cliente.put(ruta, headers=auth(token), json={**vuelo_valido(precio=30, asientos_disponibles=1), "version": 2}).status_code == 200
    assert repo.reservations[reserva.json["reserva_id"]]["total"] == importe
    assert cliente.delete(f"/api/reservas/{reserva.json['reserva_id']}", headers=auth(token)).status_code == 200
    assert vuelo["version"] == 4 and vuelo["asientos_disponibles"] == 3
    assert cliente.delete(ruta, headers=auth(token), json={"version": 3}).status_code == 409
    assert cliente.delete(ruta, headers=auth(token), json={"version": 4}).status_code == 200
    assert repo.reservations[reserva.json["reserva_id"]]["estado"] == "cancelada"


@pytest.mark.parametrize("segundo", ["put", "delete"])
def test_dos_administradores_misma_version_solo_uno_modifica(api, segundo):
    cliente, repo, token, vuelo = preparar(api)
    barrera = Barrier(2)
    def ejecutar(metodo):
        with cliente.application.test_client() as paralelo:
            barrera.wait()
            return getattr(paralelo, metodo)(f"/api/vuelos/{vuelo['id']}", headers=auth(token),
                                            json={**vuelo_valido(precio=25), "version": 1}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        resultados = list(pool.map(ejecutar, ["put", segundo]))
    assert sorted(resultados) in ([[200, 409], [200, 404]] if segundo == "delete" else [[200, 409]])
    assert vuelo["version"] == 2


def test_reserva_compite_con_eliminacion_sin_reserva_huerfana(api):
    cliente, repo, token, vuelo = preparar(api)
    barrera = Barrier(2)
    def reservar():
        with cliente.application.test_client() as paralelo:
            barrera.wait()
            return paralelo.post("/api/reservas", headers=auth(token), json={"vuelo_id": vuelo["id"], "cantidad": 1}).status_code
    def eliminar():
        with cliente.application.test_client() as paralelo:
            barrera.wait()
            return paralelo.delete(f"/api/vuelos/{vuelo['id']}", headers=auth(token), json={"version": 1}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        a, b = pool.submit(reservar), pool.submit(eliminar)
        resultados = a.result(), b.result()
    assert resultados in [(201, 409), (404, 200)]
    assert not repo.reservations or vuelo["activo"] is True


@pytest.mark.parametrize("metodo", ["put", "delete"])
def test_identificador_inexistente_y_cors_put(api, metodo):
    cliente, repo, token, vuelo = preparar(api)
    respuesta = getattr(cliente, metodo)("/api/vuelos/no-es-uuid", headers=auth(token), json={**vuelo_valido(), "version": 1})
    assert respuesta.status_code == 404
    cors = cliente.options(f"/api/vuelos/{vuelo['id']}", headers={"Origin": "http://localhost:8790", "Access-Control-Request-Method": "PUT"})
    assert "PUT" in cors.headers["Access-Control-Allow-Methods"]


@pytest.mark.parametrize("cambios", [
    {"fecha": "2000-01-01"}, {"hora_llegada": "10:00"}, {"precio": "1.234"},
    {"asientos_disponibles": -1}, {"origen": "Quito sin pais"}])
def test_edicion_reutiliza_controles_de_creacion_sin_mutar(api, cambios):
    cliente, repo, token, vuelo = preparar(api)
    antes = dict(vuelo)
    respuesta = cliente.put(f"/api/vuelos/{vuelo['id']}", headers=auth(token),
                            json={**vuelo_valido(**cambios), "version": 1})
    assert respuesta.status_code == 400 and vuelo == antes


def test_campos_internos_no_se_pueden_inyectar_al_crear(api):
    cliente, repo, token, vuelo = preparar(api)
    creado = cliente.post("/api/vuelos", headers=auth(token),
                           json={**vuelo_valido(), "version": 99, "activo": False})
    assert creado.status_code == 201
    assert creado.json["vuelo"]["version"] == 1 and creado.json["vuelo"]["activo"] is True


def test_reserva_compite_con_edicion_sin_reponer_inventario_vendido(api):
    cliente, repo, token, vuelo = preparar(api)
    barrera = Barrier(2)
    def reservar():
        with cliente.application.test_client() as paralelo:
            barrera.wait()
            return paralelo.post("/api/reservas", headers=auth(token), json={"vuelo_id": vuelo["id"], "cantidad": 1}).status_code
    def editar():
        with cliente.application.test_client() as paralelo:
            barrera.wait()
            return paralelo.put(f"/api/vuelos/{vuelo['id']}", headers=auth(token),
                                json={**vuelo_valido(precio=20), "version": 1}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        a, b = pool.submit(reservar), pool.submit(editar)
        reserva, edicion = a.result(), b.result()
    assert reserva == 201 and edicion in [200, 409]
    assert vuelo["asientos_disponibles"] == 2
    assert vuelo["version"] == (3 if edicion == 200 else 2)
    assert len(repo.reservations) == 1
