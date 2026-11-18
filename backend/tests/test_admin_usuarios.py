"""Administrative user operations through the HTTP boundary."""
import pytest
from werkzeug.security import check_password_hash

from backend.tests.test_api import api, auth, login, token_para
from backend.tests.test_roles import admin_token

NEW_USER = {'nombre': '  Nueva Persona ', 'correo': ' NUEVA@example.com ',
            'contrasena': 'UnaClaveSegura123'}


def test_legacy_promotion_preserves_exact_missing_user_response(api):
    client, repo = api
    token = admin_token(client, repo)
    response = client.post('/api/admin/usuarios/missing/promover', headers=auth(token))
    assert response.status_code == 404
    assert response.json == {'error': {
        'codigo': 'usuario_no_encontrado',
        'mensaje': 'No se encontro el usuario solicitado.',
    }}


@pytest.mark.parametrize('method,path,body', [
    ('post', '/api/admin/usuarios', NEW_USER),
    ('put', '/api/admin/usuarios/usuario-1/rol', {'rol': 'USER'}),
])
def test_user_management_requires_current_admin(api, method, path, body):
    client, repo = api
    assert getattr(client, method)(path, json=body).status_code == 401
    token = token_para(client)
    assert getattr(client, method)(path, json=body, headers=auth(token)).status_code == 403
    assert len(repo.users) == 1


@pytest.mark.parametrize('role', ['USER', 'ADMIN'])
def test_admin_creates_account_without_replacing_operator_session(api, role):
    client, repo = api
    token = admin_token(client, repo)
    response = client.post('/api/admin/usuarios', json={**NEW_USER, 'rol': role}, headers=auth(token))
    assert response.status_code == 201
    user = response.json['usuario']
    assert user['nombre'] == 'Nueva Persona' and user['correo'] == 'nueva@example.com'
    assert user['rol'] == role
    assert set(user) == {'id', 'nombre', 'correo', 'rol', 'activo'}
    assert 'token' not in response.json and 'contrasena' not in response.get_data(as_text=True)
    assert check_password_hash(repo.users[user['correo']]['password_hash'], NEW_USER['contrasena'])
    assert client.get('/api/auth/perfil', headers=auth(token)).json['usuario']['correo'] == 'ana@example.com'
    assert login(client, correo=user['correo'], contrasena=NEW_USER['contrasena']).status_code == 200


def test_default_role_validation_and_duplicate_do_not_mutate(api):
    client, repo = api
    token = admin_token(client, repo)
    response = client.post('/api/admin/usuarios', json=NEW_USER, headers=auth(token))
    assert response.status_code == 201 and response.json['usuario']['rol'] == 'USER'
    assert client.post('/api/admin/usuarios', json=NEW_USER, headers=auth(token)).status_code == 409
    for body in [{**NEW_USER, 'rol': 'owner'}, {**NEW_USER, 'contrasena': 'short'}, None]:
        assert client.post('/api/admin/usuarios', json=body, headers=auth(token)).status_code == 400
    assert len(repo.users) == 2


def test_demote_another_admin_revokes_existing_token_privileges_not_login(api):
    client, repo = api
    token = admin_token(client, repo)
    other = token_para(client, 'beto@example.com')
    repo.users['beto@example.com']['rol'] = 'ADMIN'
    response = client.put('/api/admin/usuarios/usuario-2/rol', json={'rol': 'USER'}, headers=auth(token))
    assert response.status_code == 200 and response.json['usuario']['rol'] == 'USER'
    assert client.get('/api/admin/usuarios', headers=auth(other)).status_code == 403
    assert client.get('/api/auth/perfil', headers=auth(other)).json['usuario']['rol'] == 'USER'
    assert client.put('/api/admin/usuarios/usuario-1/rol', json={'rol': 'USER'}, headers=auth(token)).status_code == 400
    assert client.put('/api/admin/usuarios/missing/rol', json={'rol': 'USER'}, headers=auth(token)).status_code == 404
    assert client.put('/api/admin/usuarios/usuario-1/rol', json={'rol': 'bad'}, headers=auth(token)).status_code == 400
    assert repo.users['ana@example.com']['rol'] == 'ADMIN'
