"""API REST de reservas de vuelos."""
import os
import xml.etree.ElementTree as ET
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from dotenv import load_dotenv
from functools import wraps
from flask import Flask, Response, g, jsonify, request
from backend.models import ErrorAPI, reserva_publica, usuario_publico
from backend.repository import RepositorioSupabase
from backend.services import (ServicioAutenticacion, validar_filtros_vuelos,
                              validar_login, validar_registro, validar_reserva)

def create_app(repository=None, jwt_secret=None):
    load_dotenv(Path(__file__).with_name('.env'))
    app = Flask(__name__)
    secreto = jwt_secret or os.getenv("JWT_SECRET")
    if repository is None:
        url, clave = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_SERVICE_KEY")
        if not url or not clave or not secreto:
            raise RuntimeError("Configura SUPABASE_URL, SUPABASE_SERVICE_KEY y JWT_SECRET.")
        if len(secreto.encode("utf-8")) < 32:
            raise RuntimeError("JWT_SECRET debe tener al menos 32 bytes.")
        repository = RepositorioSupabase.desde_entorno(url, clave)
    elif not secreto or len(secreto.encode("utf-8")) < 32:
        raise RuntimeError("JWT_SECRET debe tener al menos 32 bytes.")

    auth = ServicioAutenticacion(repository, secreto, int(os.getenv("JWT_EXPIRES_MINUTES", "60")))

    @app.errorhandler(ErrorAPI)
    def error_api(error):
        return jsonify({"error": {"codigo": error.codigo, "mensaje": error.mensaje}}), error.estado_http

    @app.errorhandler(404)
    def no_encontrado(_error):
        return jsonify({"error": {"codigo": "no_encontrado", "mensaje": "El recurso solicitado no existe."}}), 404

    @app.errorhandler(405)
    def metodo_no_permitido(_error):
        return jsonify({"error": {"codigo": "metodo_no_permitido", "mensaje": "El metodo HTTP no esta permitido."}}), 405

    @app.errorhandler(Exception)
    def error_interno(_error):
        app.logger.exception("Error interno al procesar la solicitud")
        return jsonify({"error": {"codigo": "error_interno", "mensaje": "Ocurrio un error interno."}}), 500

    def requiere_autenticacion(funcion):
        @wraps(funcion)
        def protegida(*args, **kwargs):
            esquema, separador, token = request.headers.get("Authorization", "").partition(" ")
            if esquema.lower() != "bearer" or not separador or not token:
                raise ErrorAPI("autenticacion_requerida", "Se requiere un token Bearer valido.", 401)
            g.usuario = auth.autenticar(token)
            return funcion(*args, **kwargs)
        return protegida

    @app.route("/api/usuarios/registro", methods=["POST"])
    def registrar_usuario():
        nombre, correo, contrasena = validar_registro(request.get_json(silent=True))
        usuario = auth.registrar(nombre, correo, contrasena)
        return jsonify({"mensaje": "Usuario registrado correctamente.", "usuario": usuario_publico(usuario)}), 201

    @app.route("/api/auth/login", methods=["POST"])
    def iniciar_sesion():
        correo, contrasena = validar_login(request.get_json(silent=True))
        usuario, token = auth.iniciar_sesion(correo, contrasena)
        return jsonify({"mensaje": "Inicio de sesion correcto.", "token": token, "usuario": usuario_publico(usuario)}), 200

    @app.route("/api/vuelos", methods=["GET"])
    def obtener_vuelos():
        filtros = validar_filtros_vuelos(
            request.args.get("origen"), request.args.get("destino"), request.args.get("fecha")
        )
        return jsonify(repository.listar_vuelos(**filtros)), 200

    @app.route("/api/reservas", methods=["POST"])
    @requiere_autenticacion
    def crear_reserva():
        vuelo_id, cantidad = validar_reserva(request.get_json(silent=True))
        reserva = repository.crear_reserva(g.usuario["id"], vuelo_id, cantidad)
        return jsonify({
            "mensaje": "Reserva creada correctamente.",
            "reserva_id": reserva["id"],
            "subtotal": float(reserva["subtotal"]),
            "iva": float(reserva["iva"]),
            "porcentaje_iva": float(reserva["porcentaje_iva"]),
            "total": float(reserva["total"]),
            "estado": reserva["estado"],
        }), 201

    @app.route("/api/reservas/<reserva_id>", methods=["GET"])
    @requiere_autenticacion
    def obtener_reserva(reserva_id):
        reserva = repository.obtener_reserva(reserva_id, g.usuario["id"])
        if reserva is None:
            raise ErrorAPI("reserva_no_encontrada", "No se encontro la reserva solicitada.", 404)
        return jsonify({"reserva": reserva_publica(reserva)}), 200

    @app.route("/api/reservas/<reserva_id>/comprobante.xml", methods=["GET"])
    @requiere_autenticacion
    def obtener_comprobante_xml(reserva_id):
        reserva = repository.obtener_reserva(reserva_id, g.usuario["id"])
        if reserva is None:
            raise ErrorAPI("reserva_no_encontrada", "No se encontro la reserva solicitada.", 404)
        usuario = repository.buscar_usuario_por_id(g.usuario["id"])

        raiz = ET.Element("comprobante", {"tipo": "reserva", "fiscal": "false"})
        ET.SubElement(raiz, "numero").text = str(reserva["id"])
        ET.SubElement(raiz, "fecha").text = str(reserva["creado_en"])
        ET.SubElement(raiz, "cliente").text = str((usuario or {}).get("nombre", ""))
        ET.SubElement(raiz, "vuelo_id").text = str(reserva["vuelo_id"])
        ET.SubElement(raiz, "pasajeros").text = str(reserva["cantidad"])
        ET.SubElement(raiz, "subtotal").text = _importe_xml(reserva["subtotal"])
        ET.SubElement(
            raiz,
            "iva",
            {"porcentaje": _importe_xml(reserva["porcentaje_iva"])},
        ).text = _importe_xml(reserva["iva"])
        ET.SubElement(raiz, "total").text = _importe_xml(reserva["total"])
        ET.SubElement(raiz, "nota").text = "Comprobante academico de reserva; no es un documento fiscal."
        contenido = ET.tostring(raiz, encoding="utf-8", xml_declaration=True)
        return Response(contenido, content_type="application/xml; charset=utf-8")

    @app.route("/api/reservas", methods=["GET"])
    @requiere_autenticacion
    def listar_reservas():
        reservas = repository.listar_reservas(g.usuario["id"])
        return jsonify([reserva_publica(item) for item in reservas]), 200

    @app.route("/api/reservas/<reserva_id>", methods=["DELETE"])
    @requiere_autenticacion
    def cancelar_reserva(reserva_id):
        reserva = repository.cancelar_reserva(reserva_id, g.usuario["id"])
        if reserva is None:
            raise ErrorAPI("reserva_no_encontrada", "No se encontro la reserva solicitada.", 404)
        return jsonify({"mensaje": "Reserva cancelada correctamente.", "reserva_id": reserva["id"], "estado": reserva["estado"]}), 200

    return app


def _importe_xml(valor):
    importe = Decimal(str(valor)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return format(importe, ".2f")

if __name__ == "__main__":
    application = create_app()
    application.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=False)



