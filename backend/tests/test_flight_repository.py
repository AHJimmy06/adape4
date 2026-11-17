"""Contratos del adaptador RPC sin conexion a datos reales."""
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest

from backend.models import ErrorAPI
from backend.repository import RepositorioSupabase


class ClienteSimulado:
    def __init__(self, datos=None, error=None):
        self.datos = datos or {"id": "v", "activo": True, "version": 2}
        self.error = error
        self.llamadas = []

    def rpc(self, nombre, parametros):
        self.llamadas.append((nombre, parametros))
        return self

    def table(self, nombre):
        self.llamadas.append(("table", nombre))
        return self

    def select(self, campos):
        self.llamadas.append(("select", campos))
        return self

    def eq(self, campo, valor):
        self.llamadas.append(("eq", campo, valor))
        return self

    def order(self, campo):
        return self

    def execute(self):
        if self.error:
            raise RuntimeError(self.error)
        return SimpleNamespace(data=self.datos)


def test_edicion_y_eliminacion_usan_rpc_con_version_sin_lectura_previa():
    cliente = ClienteSimulado()
    repo = RepositorioSupabase(cliente)
    identificador = str(uuid4())
    datos = {"precio": 12, "asientos_disponibles": 0}
    assert repo.modificar_vuelo(identificador, datos, 4)["version"] == 2
    assert cliente.llamadas == [("modificar_vuelo", {"p_vuelo_id": identificador, "p_version": 4, "p_datos": datos})]
    cliente.llamadas.clear()
    repo.eliminar_vuelo(identificador, 4)
    assert cliente.llamadas == [("eliminar_vuelo", {"p_vuelo_id": identificador, "p_version": 4})]


@pytest.mark.parametrize("mensaje,codigo,estado", [
    ("VUELO_MODIFICADO", "vuelo_modificado", 409),
    ("VUELO_CON_RESERVAS", "vuelo_con_reservas", 409),
    ("VUELO_INEXISTENTE", "vuelo_no_encontrado", 404)])
def test_rpc_traduce_conflictos_del_servidor(mensaje, codigo, estado):
    repo = RepositorioSupabase(ClienteSimulado(error=mensaje))
    with pytest.raises(ErrorAPI) as error:
        repo.eliminar_vuelo(str(uuid4()), 1)
    assert error.value.codigo == codigo and error.value.estado_http == estado


def test_uuid_invalido_no_llama_rpc():
    cliente = ClienteSimulado()
    with pytest.raises(ErrorAPI) as error:
        RepositorioSupabase(cliente).eliminar_vuelo("no-es-uuid", 1)
    assert error.value.estado_http == 404 and cliente.llamadas == []


def test_listado_filtra_vuelos_activos():
    cliente = ClienteSimulado(datos=[{"id": "v", "activo": True}])
    assert len(RepositorioSupabase(cliente).listar_vuelos()) == 1
    assert ("eq", "activo", True) in cliente.llamadas


def test_migracion_incrementa_version_en_stock_y_serializa_mutaciones():
    root = Path(__file__).resolve().parents[2]
    sql = (root / "database/migrations/005_crud_vuelos_concurrencia.sql").read_text(encoding="utf-8").lower()
    assert sql.strip().startswith("begin;") and sql.strip().endswith("commit;")
    assert "add column if not exists activo boolean not null default true" in sql
    assert "add column if not exists version integer not null default 1" in sql
    assert "before update on public.vuelos" in sql and "new.version := old.version + 1" in sql
    assert sql.count("where id = p_vuelo_id and activo for update;") == 2
    assert "vuelo_actual.version <> p_version" in sql
    assert "estado = 'activa'" in sql and "set activo = false" in sql
    assert "and activo" in sql and "asientos_disponibles >= p_cantidad" in sql
    assert "from public, anon, authenticated" in sql and "to service_role" in sql
    assert "delete from" not in sql and "drop table" not in sql
