from backend.app import create_app
from backend.tests.test_api import FakeRepository


def test_integral_catalog_public_route_exists():
    app = create_app(FakeRepository(), 'x' * 40)
    response = app.test_client().get('/api/sistema/aeropuertos')
    assert response.status_code != 404


def test_integral_checkout_is_authenticated():
    app = create_app(FakeRepository(), 'x' * 40)
    assert app.test_client().post('/api/sistema/pedidos', json={}).status_code == 401


def test_integral_webhook_requires_signature():
    app = create_app(FakeRepository(), 'x' * 40)
    assert app.test_client().post('/api/stripe/webhook', data=b'{}').status_code in (400, 503)
