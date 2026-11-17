"""Retired legacy writes remain authenticated, role-protected and CORS-aware.
The replacement's real SQL edit/delete/race coverage is test_sistema_integracion.
"""
import pytest
from backend.tests.test_api import api, auth, token_para


@pytest.mark.parametrize('method,path', [('post','/api/vuelos'),('put','/api/vuelos/vuelo-1'),('delete','/api/vuelos/vuelo-1')])
def test_legacy_flight_mutations_retired_only_after_authorization(api,method,path):
    client,repo=api
    before=[dict(f) for f in repo.flights]
    assert getattr(client,method)(path,json={}).status_code == 401
    token=token_para(client)
    assert getattr(client,method)(path,headers=auth(token),json={}).status_code == 403
    repo.users['ana@example.com']['rol']='ADMIN'
    response=getattr(client,method)(path,headers=auth(token),json={'version':1})
    assert response.status_code == 410
    assert response.json['error']['codigo']=='flujo_retirado'
    assert repo.flights == before


def test_cors_keeps_put_delete_for_new_and_retired_routes(api):
    client,_=api
    for path in ('/api/vuelos/vuelo-1','/api/sistema/vuelos/00000000-0000-4000-8000-000000000001'):
        response=client.options(path,headers={'Origin':'http://localhost:8790','Access-Control-Request-Method':'PUT'})
        assert response.status_code == 200
        assert 'PUT' in response.headers['Access-Control-Allow-Methods']
        assert 'DELETE' in response.headers['Access-Control-Allow-Methods']
