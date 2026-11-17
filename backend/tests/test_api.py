import threading
import xml.etree.ElementTree as ET
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timezone

import pytest

from backend.app import create_app
from backend.models import ErrorAPI


class FakeRepository:
    def __init__(self):
        self.users = {}
        self.tokens = {}
        self.flights = [{
            "id": "vuelo-1",
            "origen": "Quito",
            "destino": "Guayaquil",
            "fecha": "2026-12-01",
            "hora_salida": "10:00:00",
            "hora_llegada": "11:00:00",
            "precio": 50.0,
            "asientos_disponibles": 2,
        }, {
            "id": "vuelo-2",
            "origen": "Quito",
            "destino": "Cuenca",
            "fecha": "2026-12-02",
            "hora_salida": "12:00:00",
            "hora_llegada": "13:00:00",
            "precio": 35.0,
            "asientos_disponibles": 5,
        }]
        for flight in self.flights:
            flight.update(version=1, activo=True)
        self.reservations = {}
        self._lock = threading.Lock()

    def registrar_usuario(self, nombre, correo, password_hash):
        if correo in self.users:
            raise ValueError("correo duplicado")
        user = {"id": f"usuario-{len(self.users) + 1}", "nombre": nombre,
                "correo": correo, "password_hash": password_hash, "rol": "USER"}
        self.users[correo] = user
        return user

    def buscar_usuario_por_correo(self, correo):
        return self.users.get(correo)

    def buscar_usuario_por_id(self, usuario_id):
        return next((user for user in self.users.values() if user["id"] == usuario_id), None)

    def listar_usuarios(self):
        return list(self.users.values())

    def promover_usuario(self, usuario_id):
        user = self.buscar_usuario_por_id(usuario_id)
        if user:
            user["rol"] = "ADMIN"
        return user

    def crear_vuelo(self, datos):
        flight = {"id": f"vuelo-{len(self.flights) + 1}", **datos, "version": 1, "activo": True}
        self.flights.append(flight)
        return flight

    def crear_token(self, usuario_id, token_id, expira_en):
        self.tokens[token_id] = usuario_id

    def token_esta_activo(self, usuario_id, token_id):
        return self.tokens.get(token_id) == usuario_id

    def listar_vuelos(self, origen=None, destino=None, fecha=None):
        vuelos = [vuelo for vuelo in self.flights if vuelo["activo"]]
        for campo, filtro in (("origen", origen), ("destino", destino), ("fecha", fecha)):
            if filtro:
                vuelos = [vuelo for vuelo in vuelos if filtro.casefold() in vuelo[campo].casefold()]
        return vuelos

    def crear_reserva(self, usuario_id, vuelo_id, cantidad):
        with self._lock:
            flight = next((item for item in self.flights if item["id"] == vuelo_id and item["activo"]), None)
            if flight is None:
                raise ErrorAPI("vuelo_no_encontrado", "No se encontro el vuelo solicitado.", 404)
            if flight["asientos_disponibles"] < cantidad:
                raise ErrorAPI("asientos_insuficientes", "No hay suficientes asientos disponibles.", 409)
            flight["asientos_disponibles"] -= cantidad
            flight["version"] += 1
            reservation = {"id": f"reserva-{len(self.reservations) + 1}",
                           "usuario_id": usuario_id, "vuelo_id": vuelo_id,
                           "cantidad": cantidad, "estado": "activa",
                           "creado_en": datetime.now(timezone.utc).isoformat()}
            reservation["subtotal"] = (Decimal(str(flight["precio"])) * cantidad).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            reservation["porcentaje_iva"] = Decimal("15.00")
            reservation["iva"] = (reservation["subtotal"] * Decimal("0.15")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            reservation["total"] = reservation["subtotal"] + reservation["iva"]
            self.reservations[reservation["id"]] = reservation
            return reservation

    def obtener_reserva(self, reserva_id, usuario_id):
        reservation = self.reservations.get(reserva_id)
        return reservation if reservation and reservation["usuario_id"] == usuario_id else None

    def listar_reservas(self, usuario_id):
        return [item for item in self.reservations.values() if item["usuario_id"] == usuario_id]

    def cancelar_reserva(self, reserva_id, usuario_id):
        with self._lock:
            reservation = self.obtener_reserva(reserva_id, usuario_id)
            if reservation is None or reservation["estado"] != "activa":
                return None
            reservation["estado"] = "cancelada"
            flight = next(item for item in self.flights if item["id"] == reservation["vuelo_id"])
            flight["asientos_disponibles"] += reservation["cantidad"]
            flight["version"] += 1
            return reservation

    def _vuelo_vigente(self, vuelo_id, version):
        flight = next((v for v in self.flights if v["id"] == vuelo_id and v["activo"]), None)
        if flight is None:
            raise ErrorAPI("vuelo_no_encontrado", "No se encontro el vuelo solicitado.", 404)
        if flight["version"] != version:
            raise ErrorAPI("vuelo_modificado", "El vuelo cambio. Actualiza la lista.", 409)
        return flight

    def modificar_vuelo(self, vuelo_id, datos, version):
        with self._lock:
            flight = self._vuelo_vigente(vuelo_id, version)
            flight.update(datos)
            flight["version"] += 1
            return flight

    def eliminar_vuelo(self, vuelo_id, version):
        with self._lock:
            flight = self._vuelo_vigente(vuelo_id, version)
            if any(r["vuelo_id"] == vuelo_id and r["estado"] == "activa" for r in self.reservations.values()):
                raise ErrorAPI("vuelo_con_reservas", "No se puede eliminar un vuelo con asientos reservados.", 409)
            flight.update(activo=False, version=version + 1)
            return flight


@pytest.fixture
def api():
    repo = FakeRepository()
    app = create_app(repository=repo, jwt_secret="secreto-de-prueba-largo-para-pruebas")
    app.config.update(TESTING=True)
    return app.test_client(), repo


def registrar(client, correo="ana@example.com", contrasena="ClaveSegura123"):
    return client.post("/api/usuarios/registro", json={
        "nombre": "Ana", "correo": correo, "contrasena": contrasena,
    })


def login(client, correo="ana@example.com", contrasena="ClaveSegura123"):
    return client.post("/api/auth/login", json={"correo": correo, "contrasena": contrasena})


def token_para(client, correo="ana@example.com"):
    registrar(client, correo=correo)
    response = login(client, correo=correo)
    return response.get_json()["token"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def test_registro_valida_datos_y_no_expone_hash(api):
    client, repo = api
    invalid = client.post("/api/usuarios/registro", json={"nombre": "", "correo": "x", "contrasena": "123"})
    assert invalid.status_code == 400
    assert invalid.is_json and "error" in invalid.get_json()

    response = registrar(client)
    assert response.status_code == 201
    assert response.get_json()["usuario"] == {"id": "usuario-1", "nombre": "Ana", "correo": "ana@example.com", "rol": "USER"}
    assert response.get_json()["mensaje"]
    assert "password_hash" not in response.get_json()["usuario"]
    assert repo.users["ana@example.com"]["password_hash"] != "ClaveSegura123"
    assert registrar(client).status_code == 409


def test_login_autentica_y_rutas_privadas_exigen_jwt(api):
    client, _ = api
    registrar(client)
    assert login(client, contrasena="incorrecta").status_code == 401
    assert client.get("/api/reservas").status_code == 401

    response = login(client)
    assert response.status_code == 200
    assert response.get_json()["token"]
    assert response.get_json()["mensaje"]
    assert client.get("/api/reservas", headers=auth(response.get_json()["token"])).status_code == 200
    assert client.get("/api/reservas", headers=auth("token-invalido")).status_code == 401


def test_consulta_vuelos_devuelve_json_con_campos_flutter(api):
    client, _ = api
    response = client.get("/api/vuelos")
    assert response.status_code == 200
    vuelo = response.get_json()[0]
    assert vuelo["destino"] == "Guayaquil"
    assert all(key in vuelo for key in ("fecha", "hora_salida", "hora_llegada", "precio", "asientos_disponibles"))


def test_consulta_vuelos_aplica_filtros_de_origen_destino_y_fecha(api):
    client, _ = api
    response = client.get("/api/vuelos?origen=Quito&destino=Cuenca&fecha=2026-12-02")
    assert response.status_code == 200
    assert [vuelo["id"] for vuelo in response.get_json()] == ["vuelo-2"]


def test_reserva_se_asocia_al_usuario_autenticado_y_rechaza_cantidad_invalida(api):
    client, repo = api
    token = token_para(client)
    response = client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": 1}, headers=auth(token))
    assert response.status_code == 201
    data = response.get_json()
    assert data["reserva_id"] == "reserva-1"
    assert data["subtotal"] == 50.0
    assert data["iva"] == 7.5
    assert data["total"] == 57.5
    assert data["estado"] == "activa" and data["mensaje"]
    assert repo.reservations["reserva-1"]["usuario_id"] == repo.users["ana@example.com"]["id"]
    reservas_antes = dict(repo.reservations)
    asientos_antes = repo.flights[0]["asientos_disponibles"]
    assert client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": True}, headers=auth(token)).status_code == 400
    assert repo.reservations == reservas_antes
    assert repo.flights[0]["asientos_disponibles"] == asientos_antes


def test_rpc_atomico_no_sobrevende_asientos(api):
    client, _ = api
    token = token_para(client)
    barrier = threading.Barrier(3)
    responses = []

    def reservar():
        barrier.wait()
        responses.append(client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": 2}, headers=auth(token)))

    workers = [threading.Thread(target=reservar) for _ in range(2)]
    for worker in workers:
        worker.start()
    barrier.wait()
    for worker in workers:
        worker.join()

    assert sorted(response.status_code for response in responses) == [201, 409]


def test_usuario_solo_puede_consultar_y_cancelar_su_reserva(api):
    client, repo = api
    token_ana = token_para(client)
    token_beto = token_para(client, correo="beto@example.com")
    created = client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": 1}, headers=auth(token_ana))
    reservation_id = created.get_json()["reserva_id"]

    own_reservations = client.get("/api/reservas", headers=auth(token_ana))
    assert own_reservations.status_code == 200
    assert own_reservations.get_json()[0]["subtotal"] == 50.0
    assert own_reservations.get_json()[0]["iva"] == 7.5
    assert own_reservations.get_json()[0]["total"] == 57.5

    assert client.get(f"/api/reservas/{reservation_id}", headers=auth(token_beto)).status_code == 404
    assert client.delete(f"/api/reservas/{reservation_id}", headers=auth(token_beto)).status_code == 404
    assert client.get("/api/reservas", headers=auth(token_beto)).get_json() == []
    assert client.delete(f"/api/reservas/{reservation_id}", headers=auth(token_ana)).status_code == 200
    assert client.get(f"/api/reservas/{reservation_id}", headers=auth(token_ana)).get_json()["reserva"]["estado"] == "cancelada"
    assert repo.flights[0]["asientos_disponibles"] == 2


def test_comprobante_xml_es_protegido_valido_y_solo_del_propietario(api):
    client, repo = api
    token_ana = token_para(client)
    token_beto = token_para(client, correo="beto@example.com")
    repo.users["ana@example.com"]["nombre"] = "Ana & <Ríos>"
    created = client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": 1}, headers=auth(token_ana))
    reserva_id = created.get_json()["reserva_id"]
    ruta = f"/api/reservas/{reserva_id}/comprobante.xml"
    reserva_antes = dict(repo.reservations[reserva_id])
    asientos_antes = repo.flights[0]["asientos_disponibles"]

    assert client.get(ruta).status_code == 401
    assert client.get(ruta, headers=auth(token_beto)).status_code == 404
    assert repo.reservations[reserva_id] == reserva_antes
    assert repo.flights[0]["asientos_disponibles"] == asientos_antes
    response = client.get(ruta, headers=auth(token_ana))

    assert response.status_code == 200
    assert response.mimetype == "application/xml"
    assert "Ana &amp; &lt;Ríos&gt;" in response.get_data(as_text=True)
    root = ET.fromstring(response.data)
    assert root.findtext("subtotal") == "50.00"
    assert root.findtext("iva") == "7.50"
    assert root.findtext("total") == "57.50"
    assert root.findtext("cliente") == "Ana & <Ríos>"


def test_calculo_iva_redondea_importes_a_dos_decimales(api):
    client, repo = api
    token = token_para(client)
    repo.flights[0]["precio"] = 0.10
    response = client.post("/api/reservas", json={"vuelo_id": "vuelo-1", "cantidad": 1}, headers=auth(token))

    assert response.status_code == 201
    assert response.get_json()["subtotal"] == 0.10
    assert response.get_json()["iva"] == 0.02
    assert response.get_json()["total"] == 0.12



@pytest.mark.parametrize("origen", ["http://localhost:65517", "http://127.0.0.1:8080"])
def test_preflight_permite_flutter_local_sin_autenticacion(api, origen):
    client, _ = api
    respuesta = client.options("/api/auth/login", headers={
        "Origin": origen, "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type,authorization",
    })
    assert respuesta.status_code == 200
    assert respuesta.headers.get("Access-Control-Allow-Origin") == origen
    assert "POST" in respuesta.headers["Access-Control-Allow-Methods"]
    assert "Authorization" in respuesta.headers["Access-Control-Allow-Headers"]
    assert "Content-Type" in respuesta.headers["Access-Control-Allow-Headers"]
    assert "Origin" in respuesta.vary
    assert "Access-Control-Allow-Credentials" not in respuesta.headers


@pytest.mark.parametrize("origen", ["https://desconocido.example", "http://localhost.evil.example:8080", "null"])
def test_cors_no_autoriza_origen_desconocido(api, origen):
    client, _ = api
    respuesta = client.options("/api/auth/login", headers={"Origin": origen, "Access-Control-Request-Method":"POST"})
    assert "Access-Control-Allow-Origin" not in respuesta.headers


def test_login_y_errores_conservan_cors_y_jwt(api):
    client, _ = api
    registrar(client)
    origen = {"Origin":"http://localhost:65517"}
    respuesta = client.post("/api/auth/login", headers=origen, json={"correo":"ana@example.com", "contrasena":"ClaveSegura123"})
    assert respuesta.status_code == 200
    assert respuesta.get_json()["token"]
    assert respuesta.headers["Access-Control-Allow-Origin"] == origen["Origin"]
    denegada = client.get("/api/reservas", headers=origen)
    assert denegada.status_code == 401
    assert denegada.headers["Access-Control-Allow-Origin"] == origen["Origin"]
    token = respuesta.get_json()["token"]
    protegida = client.get("/api/reservas", headers={**origen, "Authorization":f"Bearer {token}"})
    assert protegida.status_code == 200
    assert protegida.get_json() == []


def test_cors_origen_produccion_explicito(monkeypatch):
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://aerotech.example")
    app = create_app(repository=FakeRepository(), jwt_secret="secreto-de-prueba-largo-para-pruebas")
    respuesta = app.test_client().get("/api/vuelos", headers={"Origin":"https://aerotech.example"})
    assert respuesta.headers["Access-Control-Allow-Origin"] == "https://aerotech.example"
