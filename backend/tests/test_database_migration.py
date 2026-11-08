from pathlib import Path
import re


def test_migracion_de_iva_es_idempotente_y_preserva_totales_historicos():
    ruta = Path(__file__).parents[2] / "database" / "migrations" / "001_iva_reservas.sql"
    sql = ruta.read_text(encoding="utf-8").lower()
    actualizacion = sql.split("update public.reservas", maxsplit=1)[1].split("alter table", maxsplit=1)[0]

    assert "add column if not exists subtotal" in sql
    assert "add column if not exists iva" in sql
    assert "add column if not exists porcentaje_iva numeric(5, 2);" in sql
    assert "subtotal = coalesce(subtotal, total)" in actualizacion
    assert "iva = coalesce(iva, 0.00)" in actualizacion
    assert "when subtotal is null or iva is null then 0.00" in actualizacion
    assert "alter column porcentaje_iva set default 15.00" in sql
    assert "alter column porcentaje_iva set not null" in sql
    assert sql.index("update public.reservas") < sql.index("alter column porcentaje_iva set default 15.00")
    assert not re.search(r"(?:^|,)\s*total\s*=", actualizacion)
    assert "subtotal_reserva := round(vuelo_actualizado.precio * p_cantidad, 2)" in sql
    assert "porcentaje_reserva numeric(5, 2) := 15.00" in sql
