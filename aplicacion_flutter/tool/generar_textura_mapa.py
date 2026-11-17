"""Render a Natural Earth country shapefile as a bundled equirectangular PNG."""

from __future__ import annotations

import struct
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw


RUTA_DATOS = Path(__file__).parent / "data" / "ne_50m_admin_0_countries.zip"
RUTA_SALIDA = Path(__file__).parents[1] / "assets" / "textures" / "aerotech_mapa_mundi.png"
ANCHO = 2048
ALTO = 1024
ESCALA = 2


def leer_anillos(datos: bytes) -> list[list[tuple[float, float]]]:
    """Decode the polygon records from the ESRI Shapefile binary format."""
    anillos = []
    cursor = 100
    while cursor + 8 <= len(datos):
        _, longitud_palabras = struct.unpack_from(">2i", datos, cursor)
        cursor += 8
        longitud = longitud_palabras * 2
        registro = memoryview(datos)[cursor : cursor + longitud]
        cursor += longitud
        if len(registro) < 44:
            continue
        tipo = struct.unpack_from("<i", registro, 0)[0]
        if tipo not in (5, 15, 25):
            continue
        cantidad_anillos, cantidad_puntos = struct.unpack_from("<2i", registro, 36)
        inicio_partes = 44
        partes = struct.unpack_from(f"<{cantidad_anillos}i", registro, inicio_partes)
        inicio_puntos = inicio_partes + cantidad_anillos * 4
        puntos = list(struct.iter_unpack("<2d", registro[inicio_puntos : inicio_puntos + cantidad_puntos * 16]))
        finales = (*partes[1:], cantidad_puntos)
        for inicio, final in zip(partes, finales):
            anillo = puntos[inicio:final]
            if len(anillo) >= 3:
                anillos.append(anillo)
    return anillos


def desenvolver_longitudes(anillo: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Keep dateline-crossing rings continuous so they do not fill the map center."""
    resultado = [anillo[0]]
    for longitud, latitud in anillo[1:]:
        anterior = resultado[-1][0]
        while longitud - anterior > 180:
            longitud -= 360
        while longitud - anterior < -180:
            longitud += 360
        resultado.append((longitud, latitud))
    return resultado


def area_firmada(anillo: list[tuple[float, float]]) -> float:
    return sum(
        actual[0] * siguiente[1] - siguiente[0] * actual[1]
        for actual, siguiente in zip(anillo, (*anillo[1:], anillo[0]))
    ) / 2


def coordenadas_en_imagen(
    anillo: list[tuple[float, float]], desplazamiento: float = 0
) -> list[tuple[float, float]]:
    return [
        ((longitud + 180 + desplazamiento) / 360 * ANCHO * ESCALA,
         (90 - latitud) / 180 * ALTO * ESCALA)
        for longitud, latitud in anillo
    ]


def dibujar_mapa() -> Image.Image:
    ancho, alto = ANCHO * ESCALA, ALTO * ESCALA
    oceanos = Image.new("RGB", (ancho, alto))
    pixeles = oceanos.load()
    for y in range(alto):
        latitud = abs(90 - 180 * y / alto) / 90
        fraccion = min(1.0, latitud)
        color = (
            round(9 + 8 * fraccion),
            round(42 + 20 * fraccion),
            round(76 + 18 * fraccion),
        )
        for x in range(ancho):
            pixeles[x, y] = color

    tierra = Image.new("RGB", (ancho, alto), (105, 200, 183))
    mascara = Image.new("L", (ancho, alto), 0)
    dibujo_mascara = ImageDraw.Draw(mascara)
    dibujo_bordes = ImageDraw.Draw(oceanos)
    with zipfile.ZipFile(RUTA_DATOS) as archivo:
        ruta_shp = next((nombre for nombre in archivo.namelist() if nombre.endswith(".shp")), None)
        if ruta_shp is None:
            raise ValueError(f"No se encontró un Shapefile en {RUTA_DATOS}")
        registros = leer_anillos(archivo.read(ruta_shp))

    anillos = [desenvolver_longitudes(anillo) for anillo in registros]
    for anillo in anillos:
        if area_firmada(anillo) < 0:
            for desplazamiento in (-360, 0, 360):
                dibujo_mascara.polygon(
                    coordenadas_en_imagen(anillo, desplazamiento), fill=255
                )
    for anillo in anillos:
        if area_firmada(anillo) >= 0:
            for desplazamiento in (-360, 0, 360):
                dibujo_mascara.polygon(
                    coordenadas_en_imagen(anillo, desplazamiento), fill=0
                )
    oceanos.paste(tierra, mask=mascara)
    dibujo_bordes = ImageDraw.Draw(oceanos)
    for anillo in anillos:
        for desplazamiento in (-360, 0, 360):
            dibujo_bordes.line(
                coordenadas_en_imagen(anillo, desplazamiento),
                fill=(205, 250, 233),
                width=2,
                joint="curve",
            )

    return oceanos.resize((ANCHO, ALTO), Image.Resampling.LANCZOS)


def main() -> None:
    if not RUTA_DATOS.is_file():
        raise FileNotFoundError(f"Descargue el archivo Natural Earth y colóquelo en {RUTA_DATOS}")
    RUTA_SALIDA.parent.mkdir(parents=True, exist_ok=True)
    imagen = dibujar_mapa()
    imagen.save(RUTA_SALIDA, format="PNG", optimize=True)
    print(f"Textura generada: {RUTA_SALIDA} ({ANCHO}x{ALTO}, PNG, {RUTA_SALIDA.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
