"""Only recognized domain conflicts receive public, specific messages."""
from types import SimpleNamespace

import pytest

from backend.models import ErrorAPI
from backend.repository import RepositorioSupabase


class FailingClient:
    def __init__(self, message):
        self.message = message

    def rpc(self, *_args):
        def execute():
            raise RuntimeError(self.message)
        return SimpleNamespace(execute=execute)


@pytest.mark.parametrize(('message', 'code', 'expected'), [
    ('CONFLICTO: El avión ya tiene otro vuelo en ese horario', 'avion_ocupado', 'El avión ya tiene otro vuelo'),
    ('CONFLICTO: El aeropuerto de destino no dispone de cupos de aterrizaje en esa franja', 'aeropuerto_sin_cupo', 'El aeropuerto de destino'),
    ('CONFLICTO: Versión modificada SECRET_SQL', 'conflicto', 'El recurso cambió'),
    ('PROHIBIDO: private SECRET_SQL', 'acceso_denegado', 'Se requiere el rol ADMIN.'),
    ('NO_ENCONTRADO: private SECRET_SQL', 'no_encontrado', 'No se encontró'),
    ('INVALIDO: private SECRET_SQL', 'datos_invalidos', 'Los datos no cumplen'),
    ('23505 SECRET_SQL', 'conflicto', 'Ya existe'),
])
def test_conflict_mapping_is_specific_and_never_leaks_sql(message, code, expected):
    repo = RepositorioSupabase(FailingClient(message))
    with pytest.raises(ErrorAPI) as caught:
        repo.sistema_operar('guardar', 'admin', {'recurso': 'vuelos'})
    error = caught.value
    assert error.codigo == code
    assert expected in error.mensaje
    assert 'SECRET_SQL' not in error.mensaje
    assert error.estado_http == (403 if code == 'acceso_denegado' else 404 if code == 'no_encontrado' else 400 if code == 'datos_invalidos' else 409)
