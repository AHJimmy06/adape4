"""Modelos y representaciones publicas de la API."""
from dataclasses import dataclass
from typing import Any

@dataclass(frozen=True)
class ErrorAPI(Exception):
    codigo: str
    mensaje: str
    estado_http: int

def usuario_publico(usuario: dict[str, Any]) -> dict[str, Any]:
    return {"id": usuario["id"], "nombre": usuario["nombre"], "correo": usuario["correo"]}

def reserva_publica(reserva: dict[str, Any]) -> dict[str, Any]:
    datos = {campo: reserva[campo] for campo in (
        "id", "usuario_id", "vuelo_id", "cantidad", "subtotal", "iva",
        "porcentaje_iva", "total", "estado", "creado_en"
    )}
    for campo in ("subtotal", "iva", "porcentaje_iva", "total"):
        datos[campo] = float(datos[campo])
    return datos

