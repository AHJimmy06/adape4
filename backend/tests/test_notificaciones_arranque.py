"""Arranque opcional y puente privado del repositorio, sin proveedores reales."""
import sys
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock

from backend.app import create_app
from backend.repository import RepositorioSupabase
from backend.tests.test_api import FakeRepository


def test_arranque_habilitado_inicia_despachador_una_vez(monkeypatch):
    monkeypatch.setenv('MAILTRAP_ENABLED', 'true')
    monkeypatch.setenv('MAILTRAP_API_TOKEN', 'token_de_prueba_no_real')
    monkeypatch.setenv('MAILTRAP_INBOX_ID', '123')
    cliente, despachador = Mock(), Mock()
    modulo = ModuleType('backend.notificaciones')
    modulo.ClienteMailtrap = SimpleNamespace(desde_entorno=Mock(return_value=cliente))
    modulo.DespachadorCorreos = Mock(return_value=despachador)
    monkeypatch.setitem(sys.modules, 'backend.notificaciones', modulo)
    repositorio = FakeRepository()
    app = create_app(repositorio, 'x' * 40)
    modulo.DespachadorCorreos.assert_called_once_with(repositorio, cliente)
    despachador.iniciar.assert_called_once_with()
    assert app.extensions['notificaciones'] is despachador
    assert modulo.ClienteMailtrap.desde_entorno.call_args.args[0]['MAILTRAP_INBOX_ID'] == '123'


def test_arranque_deshabilitado_no_inicia_correo(monkeypatch):
    monkeypatch.setenv('MAILTRAP_ENABLED', 'false')
    modulo = ModuleType('backend.notificaciones')
    modulo.ClienteMailtrap = SimpleNamespace(desde_entorno=Mock(return_value=None))
    modulo.DespachadorCorreos = Mock()
    monkeypatch.setitem(sys.modules, 'backend.notificaciones', modulo)
    app = create_app(FakeRepository(), 'x' * 40)
    assert not app.extensions.get('notificaciones')
    modulo.DespachadorCorreos.assert_not_called()


def test_repositorio_usa_rpc_privada_sin_usuario_cliente():
    cliente = Mock()
    esperado = {'id': 'notificacion', 'token': 'lease', 'datos': {}}
    cliente.rpc.return_value.execute.return_value = SimpleNamespace(data=esperado)
    repositorio = RepositorioSupabase(cliente)
    assert repositorio.notificaciones_operar('tomar', {}) == esperado
    cliente.rpc.assert_called_once_with('notificaciones_operar', {
        'p_accion': 'tomar', 'p_datos': {},
    })
