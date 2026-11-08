"""Adaptador del repositorio para Supabase/PostgreSQL."""
from datetime import datetime, timezone
from typing import Any
from backend.models import ErrorAPI

class RepositorioSupabase:
    def __init__(self, cliente: Any):
        self.cliente = cliente

    @classmethod
    def desde_entorno(cls, url: str, clave_servicio: str) -> "RepositorioSupabase":
        from supabase import create_client
        return cls(create_client(url, clave_servicio))

    @staticmethod
    def _primero(respuesta: Any) -> dict[str, Any] | None:
        datos = respuesta.data
        return datos[0] if isinstance(datos, list) and datos else datos if isinstance(datos, dict) else None

    def registrar_usuario(self, nombre: str, correo: str, password_hash: str) -> dict[str, Any]:
        try:
            respuesta = self.cliente.table("usuarios").insert({"nombre": nombre, "correo": correo, "password_hash": password_hash}).execute()
        except Exception as error:
            if "23505" in str(error) or "unique" in str(error).lower():
                raise ValueError("correo duplicado") from error
            raise
        return self._primero(respuesta)

    def buscar_usuario_por_correo(self, correo: str) -> dict[str, Any] | None:
        return self._primero(self.cliente.table("usuarios").select("*").eq("correo", correo).limit(1).execute())

    def buscar_usuario_por_id(self, usuario_id: str) -> dict[str, Any] | None:
        return self._primero(
            self.cliente.table("usuarios").select("id,nombre").eq("id", usuario_id).limit(1).execute()
        )

    def crear_token(self, usuario_id: str, token_id: str, expira_en: str) -> None:
        self.cliente.table("tokens").insert({"id": token_id, "usuario_id": usuario_id, "expira_en": expira_en}).execute()

    def token_esta_activo(self, usuario_id: str, token_id: str) -> bool:
        ahora = datetime.now(timezone.utc).isoformat()
        respuesta = (self.cliente.table("tokens").select("id").eq("id", token_id)
                     .eq("usuario_id", usuario_id).gt("expira_en", ahora).limit(1).execute())
        return bool(respuesta.data)

    def listar_vuelos(self, origen: str | None = None, destino: str | None = None,
                     fecha: str | None = None) -> list[dict[str, Any]]:
        consulta = self.cliente.table("vuelos").select("*")
        if origen:
            consulta = consulta.ilike("origen", f"%{origen}%")
        if destino:
            consulta = consulta.ilike("destino", f"%{destino}%")
        if fecha:
            consulta = consulta.eq("fecha", fecha)
        return consulta.order("fecha").execute().data or []

    def crear_reserva(self, usuario_id: str, vuelo_id: str, cantidad: int) -> dict[str, Any]:
        try:
            respuesta = self.cliente.rpc("reservar_vuelo", {"p_vuelo_id": vuelo_id, "p_usuario_id": usuario_id, "p_cantidad": cantidad}).execute()
        except Exception as error:
            mensaje = str(error).upper()
            if "ASIENTOS_INSUFICIENTES" in mensaje:
                raise ErrorAPI("asientos_insuficientes", "No hay suficientes asientos disponibles.", 409) from error
            if "VUELO_INEXISTENTE" in mensaje:
                raise ErrorAPI("vuelo_no_encontrado", "No se encontro el vuelo solicitado.", 404) from error
            raise
        reserva = self._primero(respuesta)
        if reserva is None:
            raise RuntimeError("La operacion de reserva no devolvio datos.")
        return reserva

    def obtener_reserva(self, reserva_id: str, usuario_id: str) -> dict[str, Any] | None:
        return self._primero(self.cliente.table("reservas").select("*").eq("id", reserva_id)
                             .eq("usuario_id", usuario_id).limit(1).execute())

    def listar_reservas(self, usuario_id: str) -> list[dict[str, Any]]:
        return (self.cliente.table("reservas").select("*").eq("usuario_id", usuario_id)
                .order("creado_en", desc=True).execute().data or [])

    def cancelar_reserva(self, reserva_id: str, usuario_id: str) -> dict[str, Any] | None:
        try:
            respuesta = self.cliente.rpc("cancelar_reserva", {"p_reserva_id": reserva_id, "p_usuario_id": usuario_id}).execute()
        except Exception as error:
            if "RESERVA_NO_ENCONTRADA" in str(error).upper():
                return None
            raise
        return self._primero(respuesta)



