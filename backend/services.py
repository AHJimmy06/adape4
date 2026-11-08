"""Reglas de autenticacion y validacion compartidas por las rutas."""
import re
from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import uuid4

import jwt
from werkzeug.security import check_password_hash, generate_password_hash
from backend.models import ErrorAPI

CORREO_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

def validar_registro(datos: Any) -> tuple[str, str, str]:
    if not isinstance(datos, dict):
        raise ErrorAPI("datos_invalidos", "Se requiere un objeto JSON.", 400)
    nombre, correo, contrasena = datos.get("nombre"), datos.get("correo"), datos.get("contrasena")
    if not isinstance(nombre, str) or not nombre.strip() or len(nombre.strip()) > 120:
        raise ErrorAPI("nombre_invalido", "El nombre es obligatorio y no puede superar 120 caracteres.", 400)
    if not isinstance(correo, str) or not CORREO_RE.fullmatch(correo.strip()):
        raise ErrorAPI("correo_invalido", "Ingresa un correo electronico valido.", 400)
    if not isinstance(contrasena, str) or not 10 <= len(contrasena) <= 256:
        raise ErrorAPI("contrasena_invalida", "La contrasena debe tener entre 10 y 256 caracteres.", 400)
    return nombre.strip(), correo.strip().lower(), contrasena

def validar_login(datos: Any) -> tuple[str, str]:
    if not isinstance(datos, dict):
        raise ErrorAPI("datos_invalidos", "Se requiere un objeto JSON.", 400)
    correo, contrasena = datos.get("correo"), datos.get("contrasena")
    if not isinstance(correo, str) or not CORREO_RE.fullmatch(correo.strip()) or not isinstance(contrasena, str) or not contrasena:
        raise ErrorAPI("credenciales_invalidas", "Correo o contrasena incorrectos.", 401)
    return correo.strip().lower(), contrasena

def validar_reserva(datos: Any) -> tuple[str, int]:
    if not isinstance(datos, dict):
        raise ErrorAPI("datos_invalidos", "Se requiere un objeto JSON.", 400)
    vuelo_id, cantidad = datos.get("vuelo_id"), datos.get("cantidad", 1)
    if not isinstance(vuelo_id, str) or not vuelo_id.strip():
        raise ErrorAPI("vuelo_invalido", "El identificador del vuelo es obligatorio.", 400)
    if isinstance(cantidad, bool) or not isinstance(cantidad, int) or not 1 <= cantidad <= 9:
        raise ErrorAPI("cantidad_invalida", "La cantidad debe ser un entero entre 1 y 9.", 400)
    return vuelo_id.strip(), cantidad

def validar_filtros_vuelos(origen: Any, destino: Any, fecha: Any) -> dict[str, str | None]:
    filtros = {"origen": origen, "destino": destino, "fecha": fecha}
    for campo, valor in filtros.items():
        if valor is not None and (not isinstance(valor, str) or not valor.strip()):
            raise ErrorAPI("filtro_invalido", f"El filtro {campo} no es valido.", 400)
    if fecha is not None:
        try:
            date.fromisoformat(fecha.strip())
        except ValueError as error:
            raise ErrorAPI("fecha_invalida", "La fecha debe usar el formato AAAA-MM-DD.", 400) from error
    return {campo: valor.strip() if valor is not None else None for campo, valor in filtros.items()}

class ServicioAutenticacion:
    def __init__(self, repositorio: Any, secreto: str, duracion_minutos: int = 60):
        self.repositorio, self.secreto = repositorio, secreto
        self.duracion = timedelta(minutes=duracion_minutos)

    def registrar(self, nombre: str, correo: str, contrasena: str) -> dict[str, Any]:
        password_hash = generate_password_hash(contrasena, method="scrypt")
        try:
            return self.repositorio.registrar_usuario(nombre, correo, password_hash)
        except ValueError as error:
            if "duplicado" in str(error).lower() or "unique" in str(error).lower():
                raise ErrorAPI("correo_registrado", "Ya existe una cuenta con ese correo.", 409) from error
            raise

    def iniciar_sesion(self, correo: str, contrasena: str) -> tuple[dict[str, Any], str]:
        usuario = self.repositorio.buscar_usuario_por_correo(correo)
        if not usuario or not check_password_hash(usuario["password_hash"], contrasena):
            raise ErrorAPI("credenciales_invalidas", "Correo o contrasena incorrectos.", 401)
        ahora, token_id = datetime.now(timezone.utc), str(uuid4())
        vence = ahora + self.duracion
        token = jwt.encode({"sub": str(usuario["id"]), "jti": token_id, "iat": ahora, "exp": vence},
                           self.secreto, algorithm="HS256")
        self.repositorio.crear_token(str(usuario["id"]), token_id, vence.isoformat())
        return usuario, token

    def autenticar(self, token: str) -> dict[str, Any]:
        try:
            identidad = jwt.decode(token, self.secreto, algorithms=["HS256"])
            usuario_id, token_id = identidad.get("sub"), identidad.get("jti")
            if not usuario_id or not token_id or not self.repositorio.token_esta_activo(usuario_id, token_id):
                raise ErrorAPI("token_invalido", "El token no es valido o ha expirado.", 401)
            return {"id": usuario_id}
        except jwt.PyJWTError as error:
            raise ErrorAPI("token_invalido", "El token no es valido o ha expirado.", 401) from error

