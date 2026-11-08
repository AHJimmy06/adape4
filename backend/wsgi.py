"""Punto de entrada WSGI para el despliegue de Flask en Render."""

from backend.app import create_app

app = create_app()
