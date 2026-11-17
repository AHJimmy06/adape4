"""Public-interface coverage of role authorization and additive migrations."""
from pathlib import Path
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from backend.tests.test_api import api, auth, login, registrar, token_para


FLIGHT = {"origen": "Quito, Ecuador", "destino": "Lima, Peru",
          "fecha": (datetime.now(timezone(timedelta(hours=-5))).date() + timedelta(days=2)).isoformat(),
          "hora_salida": "09:30", "hora_llegada": "11:15",
          "precio": 50.25, "asientos_disponibles": 20}
SECRET = "secreto-de-prueba-largo-para-pruebas"


def admin_token(client, repo):
    token = token_para(client)
    repo.users["ana@example.com"]["rol"] = "ADMIN"
    return token


def test_registration_cannot_select_admin(api):
    client, repo = api
    response = client.post("/api/usuarios/registro", json={
        "nombre": "User", "correo": "new@example.com", "contrasena": "ClaveSegura123", "rol": "ADMIN"})
    assert response.status_code == 201
    assert response.json["usuario"]["rol"] == "USER"
    assert repo.users["new@example.com"]["rol"] == "USER"
    assert "password_hash" not in response.json["usuario"]
    assert login(client, correo="new@example.com").json["usuario"]["rol"] == "USER"


@pytest.mark.parametrize("method,path", [
    ("get", "/api/admin/usuarios"), ("post", "/api/admin/usuarios/usuario-1/promover"),
    ("post", "/api/vuelos")])
def test_admin_routes_reject_anonymous_and_users_without_mutation(api, method, path):
    client, repo = api
    assert getattr(client, method)(path, json=FLIGHT).status_code == 401
    token = token_para(client)
    before = [dict(flight) for flight in repo.flights]
    response = getattr(client, method)(path, json=FLIGHT, headers=auth(token))
    assert response.status_code == 403
    assert repo.users["ana@example.com"]["rol"] == "USER"
    assert repo.flights == before


def test_admin_lists_public_users_and_promotes_existing_user_with_old_token(api):
    client, repo = api
    admin = admin_token(client, repo)
    user = token_para(client, "beto@example.com")
    users = client.get("/api/admin/usuarios", headers=auth(admin))
    assert users.status_code == 200
    assert len(users.json) == 2
    assert all(set(item) == {"id", "nombre", "correo", "rol"} for item in users.json)
    assert client.get("/api/auth/perfil", headers=auth(user)).json["usuario"]["rol"] == "USER"
    promoted = client.post("/api/admin/usuarios/usuario-2/promover", headers=auth(admin), json={"rol": "USER"})
    assert promoted.status_code == 200
    assert promoted.json["usuario"]["rol"] == "ADMIN"
    assert repo.users["beto@example.com"]["rol"] == "ADMIN"
    assert client.get("/api/admin/usuarios", headers=auth(user)).status_code == 200
    assert client.get("/api/auth/perfil", headers=auth(user)).json["usuario"]["rol"] == "ADMIN"
    assert client.post("/api/admin/usuarios/missing/promover", headers=auth(admin)).status_code == 404
    assert client.post("/api/admin/usuarios/usuario-1/promover", headers=auth(admin)).status_code == 400


def test_token_role_is_ignored_and_deleted_users_are_rejected(api):
    client, repo = api
    token = token_para(client)
    claims = jwt.decode(token, SECRET, algorithms=["HS256"])
    claims["rol"] = "ADMIN"
    forged_role = jwt.encode(claims, SECRET, algorithm="HS256")
    assert client.get("/api/admin/usuarios", headers=auth(forged_role)).status_code == 403
    assert client.get("/api/auth/perfil").status_code == 401
    del repo.users["ana@example.com"]
    assert client.get("/api/auth/perfil", headers=auth(token)).status_code == 401
    assert client.get("/api/reservas", headers=auth(token)).status_code == 401


def test_admin_creates_flight_without_affecting_existing_flights(api):
    client, repo = api
    token = admin_token(client, repo)
    original = [dict(flight) for flight in repo.flights]
    response = client.post("/api/vuelos", headers=auth(token), json={**FLIGHT, "id": "injected"})
    assert response.status_code == 201
    flight = response.json["vuelo"]
    assert flight["id"] != "injected"
    assert all(flight[key] == value for key, value in FLIGHT.items())
    assert repo.flights[:2] == original
    assert client.get(f"/api/vuelos?origen=Quito&destino=Lima&fecha={FLIGHT['fecha']}").json == [flight]


@pytest.mark.parametrize("field,value", [
    ("origen", "Quito"), ("destino", "Lima, "), ("origen", ", Ecuador"),
    ("origen", "Quito, Ecuador, Other"), ("destino", "Quito, Ecuador"),
    ("fecha", "2026-02-30"), ("fecha", None), ("hora_salida", "25:00"),
    ("hora_llegada", "noon"), ("hora_llegada", None),
    ("precio", -1), ("precio", True), ("precio", "NaN"), ("precio", "Infinity"),
    ("asientos_disponibles", 0), ("asientos_disponibles", True), ("asientos_disponibles", 2.5)])
def test_invalid_flight_is_not_persisted(api, field, value):
    client, repo = api
    token = admin_token(client, repo)
    before = [dict(flight) for flight in repo.flights]
    response = client.post("/api/vuelos", headers=auth(token), json={**FLIGHT, field: value})
    assert response.status_code == 400
    assert repo.flights == before


def test_role_sql_is_additive_transactional_and_bootstrap_is_exact():
    root = Path(__file__).resolve().parents[2]
    migration = (root / "database/migrations/002_roles.sql").read_text().lower()
    bootstrap = (root / "database/migrations/003_admin_inicial.sql").read_text().lower()
    schema = (root / "database/schema.sql").read_text().lower()
    assert "begin;" in migration and "commit;" in migration
    assert "add column if not exists rol" in migration
    assert "default 'user'" in migration and "'admin', 'user'" in migration
    assert "drop table" not in migration and "delete from" not in migration
    assert "default 'user'" in schema and "rol" in schema
    assert "begin;" in bootstrap and "commit;" in bootstrap
    assert "lock table public.usuarios in exclusive mode" in bootstrap
    assert "count(*)" in bootstrap and "<> 1" in bootstrap
    assert "current_setting('ape4.admin_inicial_id', true)" in bootstrap
    assert "::uuid" in bootstrap and "is null" in bootstrap
    assert "where id = target_id" in bootstrap
    assert "raise exception" in bootstrap
    assert "delete from" not in bootstrap


@pytest.mark.parametrize("variant", ["upper", "compact"])
def test_admin_cannot_promote_self_using_alternate_uuid_spelling(api, variant):
    client, repo = api
    registrar(client)
    user_id = "11111111-2222-4333-8444-555555555555"
    repo.users["ana@example.com"].update(id=user_id, rol="ADMIN")
    token = login(client).json["token"]
    target = user_id.upper() if variant == "upper" else user_id.replace("-", "")
    response = client.post(f"/api/admin/usuarios/{target}/promover", headers=auth(token))
    assert response.status_code == 400
    assert repo.users["ana@example.com"]["rol"] == "ADMIN"


@pytest.mark.parametrize("dias", [-1, 0])
def test_admin_rejects_today_and_past_without_mutation(api, dias):
    client, repo = api
    token = admin_token(client, repo)
    fecha = (datetime.now(timezone(timedelta(hours=-5))).date() + timedelta(days=dias)).isoformat()
    before = [dict(flight) for flight in repo.flights]
    response = client.post("/api/vuelos", headers=auth(token), json={**FLIGHT, "fecha": fecha})
    assert response.status_code == 400
    assert response.json["error"]["codigo"] == "fecha_invalida"
    assert repo.flights == before


@pytest.mark.parametrize("salida,llegada", [("10:00", "10:00"), ("11:00", "10:00"), ("23:30", "01:15"), ("10:00:30", "10:00:29")])
def test_admin_rejects_arrival_not_after_departure_without_mutation(api, salida, llegada):
    client, repo = api
    token = admin_token(client, repo)
    before = [dict(flight) for flight in repo.flights]
    response = client.post("/api/vuelos", headers=auth(token), json={**FLIGHT, "hora_salida": salida, "hora_llegada": llegada})
    assert response.status_code == 400
    assert response.json["error"]["codigo"] == "hora_invalida"
    assert repo.flights == before
