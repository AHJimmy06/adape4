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
            respuesta = self.cliente.table("usuarios").insert({"nombre": nombre, "correo": correo, "password_hash": password_hash, "rol": "USER"}).execute()
        except Exception as error:
            if "23505" in str(error) or "unique" in str(error).lower():
                raise ValueError("correo duplicado") from error
            raise
        return self._primero(respuesta)

    def buscar_usuario_por_correo(self, correo: str) -> dict[str, Any] | None:
        return self._primero(self.cliente.table("usuarios").select("*").eq("correo", correo).limit(1).execute())

    def buscar_usuario_por_id(self, usuario_id: str) -> dict[str, Any] | None:
        return self._primero(
            self.cliente.table("usuarios").select("id,nombre,correo,rol,activo,version_acceso").eq("id", usuario_id).limit(1).execute()
        )

    def listar_usuarios(self) -> list[dict[str, Any]]:
        return self.cliente.table("usuarios").select("id,nombre,correo,rol,activo").order("creado_en").execute().data or []

    def administrar_usuario(self, actor_id, accion, datos):
        try:
            respuesta = self.cliente.rpc("administrar_usuario", {
                "p_actor": actor_id, "p_accion": accion, "p_datos": datos,
            }).execute()
        except Exception as error:
            mensaje = str(error).upper()
            errors = [
                ("ADMIN_REQUERIDO", "acceso_denegado", "Se requiere el rol ADMIN vigente.", 403),
                ("USUARIO_INEXISTENTE", "usuario_no_encontrado", "No se encontró el usuario solicitado.", 404),
                ("AUTO_RETIRO", "auto_retiro", "No puedes retirar tu propio acceso ADMIN.", 400),
                ("AUTO_DESACTIVACION", "auto_desactivacion", "No puedes desactivar tu propia cuenta.", 400),
                ("ULTIMO_ADMIN", "ultimo_admin", "Debe permanecer al menos un administrador.", 409),
                ("DATOS_USUARIO_INVALIDOS", "datos_invalidos", "Revisa los datos y el rol del usuario.", 400),
                ("23505", "correo_registrado", "Ya existe una cuenta con ese correo.", 409),
            ]
            for marker, code, public_message, status in errors:
                if marker in mensaje:
                    raise ErrorAPI(code, public_message, status) from error
            # Do not chain RPC failures containing password hashes into request logs.
            raise ErrorAPI("administracion_no_disponible", "No se pudo guardar el usuario. Reintenta más tarde.", 503) from None
        usuario = self._primero(respuesta)
        if usuario is None:
            raise RuntimeError("La administración de usuarios no devolvió datos.")
        return usuario

    def crear_vuelo(self, datos: dict[str, Any]) -> dict[str, Any]:
        vuelo = self._primero(self.cliente.table("vuelos").insert(datos).execute())
        if vuelo is None:
            raise RuntimeError("La creacion de vuelo no devolvio datos.")
        return vuelo

    def _mutar_vuelo(self, funcion: str, vuelo_id: str, version: int, datos=None) -> dict[str, Any]:
        from uuid import UUID
        try:
            identificador = str(UUID(vuelo_id))
        except (ValueError, TypeError, AttributeError) as error:
            raise ErrorAPI("vuelo_no_encontrado", "No se encontro el vuelo solicitado.", 404) from error
        parametros = {"p_vuelo_id": identificador, "p_version": version}
        if datos is not None:
            parametros["p_datos"] = datos
        try:
            respuesta = self.cliente.rpc(funcion, parametros).execute()
        except Exception as error:
            mensaje = str(error).upper()
            if "VUELO_MODIFICADO" in mensaje:
                raise ErrorAPI("vuelo_modificado", "El vuelo cambio mientras lo editabas. Actualiza la lista e intenta de nuevo.", 409) from error
            if "VUELO_CON_RESERVAS" in mensaje:
                raise ErrorAPI("vuelo_con_reservas", "No se puede modificar ni eliminar un vuelo con asientos reservados.", 409) from error
            if "VUELO_INEXISTENTE" in mensaje:
                raise ErrorAPI("vuelo_no_encontrado", "No se encontro el vuelo solicitado.", 404) from error
            raise
        vuelo = self._primero(respuesta)
        if vuelo is None:
            raise RuntimeError("La operacion de vuelo no devolvio datos.")
        return vuelo

    def modificar_vuelo(self, vuelo_id: str, datos: dict[str, Any], version: int) -> dict[str, Any]:
        return self._mutar_vuelo("modificar_vuelo", vuelo_id, version, datos)

    def eliminar_vuelo(self, vuelo_id: str, version: int) -> dict[str, Any]:
        return self._mutar_vuelo("eliminar_vuelo", vuelo_id, version)

    def crear_token(self, usuario_id: str, token_id: str, expira_en: str) -> None:
        self.cliente.table("tokens").insert({"id": token_id, "usuario_id": usuario_id, "expira_en": expira_en}).execute()

    def token_esta_activo(self, usuario_id: str, token_id: str) -> bool:
        ahora = datetime.now(timezone.utc).isoformat()
        respuesta = (self.cliente.table("tokens").select("id").eq("id", token_id)
                     .eq("usuario_id", usuario_id).gt("expira_en", ahora).limit(1).execute())
        return bool(respuesta.data)

    def listar_vuelos(self, origen: str | None = None, destino: str | None = None,
                     fecha: str | None = None) -> list[dict[str, Any]]:
        consulta = self.cliente.table("vuelos").select("*").eq("activo", True)
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

    def notificaciones_operar(self, accion, datos):
        """Cola privada de correos: se ejecuta con la clave de servicio."""
        return self.cliente.rpc('notificaciones_operar', {
            'p_accion': accion, 'p_datos': datos,
        }).execute().data

    def sistema_operar(self, accion, usuario_id, datos):
        try:
            return self.cliente.rpc('sistema_operar', {'p_accion': accion, 'p_usuario': usuario_id, 'p_datos': datos}).execute().data
        except Exception as error:
            message = str(error)
            if 'INVALIDO: Usuario asignado inexistente o inactivo' in message:
                raise ErrorAPI('usuario_asignado_no_disponible',
                               'El correo asignado no corresponde a un usuario activo. Revisa los datos del pasajero.', 400) from error
            schedule_conflicts = (
                ('CONFLICTO: El avión ya tiene otro vuelo en ese horario', 'avion_ocupado',
                 'El avión ya tiene otro vuelo en ese horario. Elige un intervalo libre.'),
                ('CONFLICTO: El aeropuerto de destino no dispone de cupos de aterrizaje en esa franja',
                 'aeropuerto_sin_cupo', 'El aeropuerto de destino no dispone de cupos de aterrizaje en esa franja. Elige otra hora de llegada.'),
            )
            for marker, code, public_message in schedule_conflicts:
                if marker in message:
                    raise ErrorAPI(code, public_message, 409) from error
            categories = [('PROHIBIDO:', 'acceso_denegado', 403), ('NO_ENCONTRADO:', 'no_encontrado', 404),
                          ('CONFLICTO:', 'conflicto', 409), ('INVALIDO:', 'datos_invalidos', 400)]
            for marker, code, status in categories:
                if marker in message:
                    # PostgREST exception text may contain SQL internals; don't expose it.
                    messages = {403: 'Se requiere el rol ADMIN.', 404: 'No se encontró el recurso solicitado.',
                                409: 'El recurso cambió, está ocupado o la operación ya existe. Actualiza los datos.',
                                400: 'Los datos no cumplen las reglas del sistema.'}
                    raise ErrorAPI(code, messages[status], status) from error
            if '23505' in message or 'unique constraint' in message.lower():
                raise ErrorAPI('conflicto', 'Ya existe un registro con esos datos.', 409) from error
            if any(code in message for code in ('22007', '22P02', '23514', '23503', '22023')):
                raise ErrorAPI('datos_invalidos', 'Los datos no cumplen las restricciones del sistema.', 400) from error
            raise
