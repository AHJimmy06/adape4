"""Genera la escena GLB original del globo interactivo de AeroTech."""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path


RUTA_MODELO = Path(__file__).parents[1] / "assets" / "models" / "aerotech_globo.glb"
RUTA_TEXTURA = Path(__file__).parents[1] / "assets" / "textures" / "aerotech_mapa_mundi.png"
COMPONENTE_FLOAT = 5126
COMPONENTE_UINT = 5125
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


class GeneradorGlb:
    """Escribe los buffers y metadatos binarios del formato glTF 2.0."""

    def __init__(self) -> None:
        self.binario = bytearray()
        self.vistas: list[dict] = []
        self.accesores: list[dict] = []

    def agregar_accesor(
        self,
        valores: list[tuple[float, ...]] | list[int],
        tipo: str,
        componente: int,
        objetivo: int | None = None,
        limites: bool = False,
    ) -> int:
        while len(self.binario) % 4:
            self.binario.append(0)
        inicio = len(self.binario)
        dimensiones = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[tipo]
        es_float = componente == COMPONENTE_FLOAT
        formato = "f" if es_float else "I"
        for valor in valores:
            fila = (valor,) if isinstance(valor, (int, float)) else valor
            self.binario.extend(struct.pack("<" + formato * dimensiones, *fila))
        longitud = len(self.binario) - inicio

        vista = {"buffer": 0, "byteOffset": inicio, "byteLength": longitud}
        if objetivo is not None:
            vista["target"] = objetivo
        indice_vista = len(self.vistas)
        self.vistas.append(vista)

        accesor = {
            "bufferView": indice_vista,
            "componentType": componente,
            "count": len(valores),
            "type": tipo,
        }
        if limites and es_float:
            filas = [((valor,) if isinstance(valor, (int, float)) else valor) for valor in valores]
            accesor["min"] = [min(fila[i] for fila in filas) for i in range(dimensiones)]
            accesor["max"] = [max(fila[i] for fila in filas) for i in range(dimensiones)]
        indice_accesor = len(self.accesores)
        self.accesores.append(accesor)
        return indice_accesor

    def agregar_imagen_png(self, ruta: Path) -> int:
        while len(self.binario) % 4:
            self.binario.append(0)
        inicio = len(self.binario)
        datos = ruta.read_bytes()
        indice = len(self.vistas)
        self.vistas.append({"buffer": 0, "byteOffset": inicio, "byteLength": len(datos)})
        self.binario.extend(datos)
        return indice

    def guardar(self, gltf: dict, ruta: Path) -> None:
        gltf["bufferViews"] = self.vistas
        gltf["accessors"] = self.accesores
        gltf["buffers"] = [{"byteLength": len(self.binario)}]
        json_binario = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        json_binario += b" " * (-len(json_binario) % 4)
        binario = bytes(self.binario) + b"\0" * (-len(self.binario) % 4)
        longitud = 12 + 8 + len(json_binario) + 8 + len(binario)
        ruta.parent.mkdir(parents=True, exist_ok=True)
        with ruta.open("wb") as archivo:
            archivo.write(struct.pack("<4sII", b"glTF", 2, longitud))
            archivo.write(struct.pack("<I4s", len(json_binario), b"JSON"))
            archivo.write(json_binario)
            archivo.write(struct.pack("<I4s", len(binario), b"BIN\0"))
            archivo.write(binario)


def crear_esfera(
    generador: GeneradorGlb,
    radio: float,
    segmentos: int,
    paralelos: int,
) -> dict:
    posiciones: list[tuple[float, float, float]] = []
    normales: list[tuple[float, float, float]] = []
    coordenadas_uv: list[tuple[float, float]] = []
    indices: list[int] = []
    for fila in range(paralelos + 1):
        latitud = -math.pi / 2 + math.pi * fila / paralelos
        for columna in range(segmentos + 1):
            longitud = -math.pi + 2 * math.pi * columna / segmentos
            x = math.cos(latitud) * math.cos(longitud)
            y = math.sin(latitud)
            z = math.cos(latitud) * math.sin(longitud)
            posiciones.append((radio * x, radio * y, radio * z))
            normales.append((x, y, z))
            # glTF usa el origen de textura en la esquina superior izquierda;
            # la fila geométrica avanza del polo sur al norte.
            coordenadas_uv.append((columna / segmentos, 1 - fila / paralelos))
    for fila in range(paralelos):
        for columna in range(segmentos):
            a = fila * (segmentos + 1) + columna
            b = a + 1
            c = a + segmentos + 1
            d = c + 1
            indices.extend((a, c, b, b, c, d))

    atributos = {
        "POSITION": generador.agregar_accesor(posiciones, "VEC3", COMPONENTE_FLOAT, ARRAY_BUFFER, True),
        "NORMAL": generador.agregar_accesor(normales, "VEC3", COMPONENTE_FLOAT, ARRAY_BUFFER),
        "TEXCOORD_0": generador.agregar_accesor(coordenadas_uv, "VEC2", COMPONENTE_FLOAT, ARRAY_BUFFER),
    }
    indice = generador.agregar_accesor(indices, "SCALAR", COMPONENTE_UINT, ELEMENT_ARRAY_BUFFER)
    return {"attributes": atributos, "indices": indice, "mode": 4}


def crear_avion(generador: GeneradorGlb) -> dict:
    """Avión de pasajeros con fuselaje suave, alas sólidas y dos turbinas."""
    partes = []

    def guardar(vertices, normales, indices, material):
        partes.append({"attributes": {
            "POSITION": generador.agregar_accesor(vertices, "VEC3", COMPONENTE_FLOAT, ARRAY_BUFFER, True),
            "NORMAL": generador.agregar_accesor(normales, "VEC3", COMPONENTE_FLOAT, ARRAY_BUFFER),
        }, "indices": generador.agregar_accesor(indices, "SCALAR", COMPONENTE_UINT, ELEMENT_ARRAY_BUFFER),
            "material": material, "mode": 4})

    def cuerpo(perfil, centro, material, achatamiento=1.0):
        vertices, normales, indices = [], [], []
        segmentos = 32
        for j, (z, radio) in enumerate(perfil):
            anterior = perfil[max(0, j-1)]
            siguiente = perfil[min(len(perfil)-1, j+1)]
            pendiente = (siguiente[1]-anterior[1]) / (siguiente[0]-anterior[0])
            for i in range(segmentos+1):
                angulo = 2*math.pi*i/segmentos
                x, y = math.cos(angulo), math.sin(angulo)
                vertices.append((centro[0]+radio*x, centro[1]+radio*y*achatamiento, centro[2]+z))
                normal = (x, y/achatamiento, -pendiente)
                longitud = math.sqrt(sum(v*v for v in normal))
                normales.append(tuple(v/longitud for v in normal))
        for j in range(len(perfil)-1):
            for i in range(segmentos):
                k = j*(segmentos+1)+i
                indices.extend((k, k+1, k+segmentos+1, k+1, k+segmentos+2, k+segmentos+1))
        guardar(vertices, normales, indices, material)

    def superficie(contorno, espesor, material):
        # Prisma cerrado: cada cara lleva su normal, no una normal plana ficticia.
        vertices, normales, indices = [], [], []
        u = [b-a for a,b in zip(contorno[0],contorno[1])]
        v = [b-a for a,b in zip(contorno[0],contorno[2])]
        normal = (u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        longitud = math.sqrt(sum(x*x for x in normal))
        normal = tuple(x/longitud for x in normal)
        arriba = [tuple(v+n*espesor/2 for v,n in zip(p,normal)) for p in contorno]
        abajo = [tuple(v-n*espesor/2 for v,n in zip(p,normal)) for p in contorno]
        caras = [arriba, list(reversed(abajo))]
        for i in range(len(contorno)):
            j = (i+1) % len(contorno)
            caras.append([arriba[i], abajo[i], abajo[j], arriba[j]])
        for cara in caras:
            u = [b-a for a,b in zip(cara[0], cara[1])]
            v = [b-a for a,b in zip(cara[0], cara[2])]
            n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
            longitud = math.sqrt(sum(x*x for x in n))
            inicio = len(vertices)
            vertices.extend(cara)
            normales.extend([tuple(x/longitud for x in n)]*len(cara))
            for i in range(1,len(cara)-1):
                indices.extend((inicio, inicio+i, inicio+i+1))
        guardar(vertices, normales, indices, material)

    cuerpo([(-.18,0),(-.173,.014),(-.15,.025),(-.11,.03),(.08,.03),(.13,.022),(.18,.004),(.19,0)], (0,0,0), 2, .9)
    for lado in (-1,1):
        ala = [(lado*.02,-.003,-.035),(lado*.17,.008,.052),
               (lado*.165,.008,.077),(lado*.025,-.003,.048)]
        cola = [(lado*.014,.01,.105),(lado*.073,.022,.15),
                (lado*.07,.022,.169),(lado*.012,.01,.148)]
        if lado == -1:
            ala.reverse()
            cola.reverse()
        superficie(ala, .009, 3)
        superficie(cola, .007, 3)
        cuerpo([(-.048,0),(-.047,.016),(-.032,.019),(.025,.017),(.038,.012),(.039,0)],
               (lado*.073,-.025,.016), 2)
        # Entrada oscura del motor y ventanas laterales.
        cuerpo([(-.049,0),(-.0485,.012),(-.048,.012)], (lado*.073,-.025,.016), 5)
        for z in (-.09,-.065,-.04,-.015,.01,.035,.06):
            superficie([(lado*.029,.007,z),(lado*.03,.016,z),
                        (lado*.03,.016,z+.009),(lado*.029,.007,z+.009)], .002, 5)
    superficie([(0,.015,.10),(0,.082,.152),(0,.077,.179),(0,.015,.165)], .009, 3)
    cuerpo([(-.151,0),(-.146,.022),(-.127,.027),(-.12,0)], (0,.008,0), 5, .65)
    return {"name": "Avion de pasajeros detallado", "primitives": partes}


def punto_ruta(progreso: float, inicio: float) -> tuple:
    angulo = inicio + 1.65*progreso
    radio = 1.055 + .34*math.sin(math.pi*progreso)**2
    return (radio*math.cos(angulo), 0.0, radio*math.sin(angulo))


def orientar_avion(frente, radial) -> tuple:
    """Convierte el marco tangente de vuelo a un cuaternión glTF (nariz -Z)."""
    def normalizar(v):
        longitud = math.sqrt(sum(x*x for x in v))
        return tuple(x/longitud for x in v)

    def cruz(a,b):
        return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

    frente = normalizar(frente)
    derecha = normalizar(cruz(frente,radial))
    arriba = cruz(derecha,frente)
    m = [[derecha[i], arriba[i], -frente[i]] for i in range(3)]
    traza = sum(m[i][i] for i in range(3))
    if traza > 0:
        r = math.sqrt(1+traza)*2
        return ((m[2][1]-m[1][2])/r, (m[0][2]-m[2][0])/r, (m[1][0]-m[0][1])/r, r/4)
    i = max(range(3), key=lambda j: m[j][j])
    j, k = (i+1)%3, (i+2)%3
    r = math.sqrt(1+m[i][i]-m[j][j]-m[k][k])*2
    q = [0.0]*4
    q[i], q[j], q[k], q[3] = r/4, (m[j][i]+m[i][j])/r, (m[k][i]+m[i][k])/r, (m[k][j]-m[j][k])/r
    return tuple(q)


def muestras_vuelo(inicio: float) -> tuple:
    tiempos, posiciones, orientaciones = [], [], []
    for i in range(257):
        tiempo = i/8
        if tiempo <= 14:
            progreso, sentido, giro = tiempo/14, 1, 0
        elif tiempo <= 16:
            progreso, sentido, giro = 1, 1, math.pi*(tiempo-14)/2
        elif tiempo <= 30:
            progreso, sentido, giro = 1-(tiempo-16)/14, -1, 0
        else:
            progreso, sentido, giro = 0, -1, math.pi*(tiempo-30)/2
        angulo = inicio+1.65*progreso
        radial = (math.cos(angulo),0,math.sin(angulo))
        tangente = (-math.sin(angulo),0,math.cos(angulo))
        if 14 < tiempo <= 16 or tiempo > 30:
            frente = tuple(sentido*math.cos(giro)*x for x in tangente)
            frente = (frente[0], math.sin(giro), frente[2])
        else:
            dr = .34*math.pi*math.sin(2*math.pi*progreso)
            radio = 1.055+.34*math.sin(math.pi*progreso)**2
            frente = tuple(sentido*(dr*r+radio*1.65*t) for r,t in zip(radial,tangente))
        q = orientar_avion(frente,radial)
        # Continuidad de hemisferio para que la interpolación no invierta el giro.
        if orientaciones and sum(a*b for a,b in zip(q,orientaciones[-1])) < 0:
            q = tuple(-x for x in q)
        tiempos.append(tiempo)
        posiciones.append(punto_ruta(progreso,inicio))
        orientaciones.append(q)
    return tiempos, posiciones, orientaciones


def crear_ruta(generador: GeneradorGlb, inicio: float) -> dict:
    vertices, indices = [], []
    for i in range(97):
        x,_,z = punto_ruta(i/96,inicio)
        vertices.extend(((x,-.002,z),(x,.002,z)))
    for i in range(96):
        k = i*2
        indices.extend((k,k+1,k+2,k+1,k+3,k+2))
    return {"name": "Arco de vuelo", "primitives": [{"attributes": {
        "POSITION": generador.agregar_accesor(vertices,"VEC3",COMPONENTE_FLOAT,ARRAY_BUFFER,True),
        "NORMAL": generador.agregar_accesor([(0,1,0)]*len(vertices),"VEC3",COMPONENTE_FLOAT,ARRAY_BUFFER),
    },"indices": generador.agregar_accesor(indices,"SCALAR",COMPONENTE_UINT,ELEMENT_ARRAY_BUFFER),
        "material":4,"mode":4}]}


def crear_escena() -> tuple[GeneradorGlb, dict]:
    generador = GeneradorGlb()
    esfera = crear_esfera(generador, 1.0, 384, 192)
    atmosfera = crear_esfera(generador, 1.045, 48, 24)
    planeta = {"name": "Superficie terrestre", "primitives": [dict(esfera, material=0)]}
    halo = {"name": "Halo atmosferico", "primitives": [dict(atmosfera, material=1)]}
    avion = crear_avion(generador)
    meshes = [planeta, halo, avion]

    nodos = [
        {"name": "Escena AeroTech", "children": [1, 2]},
        {"name": "Planeta AeroTech", "mesh": 0},
        {"name": "Halo atmosferico", "mesh": 1},
    ]
    canales = []
    muestreadores = []
    # Dos trayectos separados en lados distintos de la esfera, sin órbitas completas.
    marcador = crear_esfera(generador, .014, 16, 8)
    meshes.append({"name":"Punto de despegue y aterrizaje", "primitives":[dict(marcador,material=3)]})
    for indice, (inicio, inclinacion) in enumerate(((.2,.48),(math.pi+.2,-.35))):
        padre = len(nodos)
        nodos[0]["children"].append(padre)
        nodos.append({"name":f"Ruta de vuelo {indice+1}",
                      "rotation":[0,0,math.sin(inclinacion/2),math.cos(inclinacion/2)],"children":[]})
        tiempos, posiciones, orientaciones = muestras_vuelo(inicio)
        trayectoria = len(nodos)
        nodos.append({"name":f"Trayectoria {indice+1}","translation":posiciones[0],
                      "rotation":orientaciones[0],"children":[trayectoria+1]})
        nodos.append({"name":f"Avion de ruta {indice+1}","mesh":2,"scale":[.85,.85,.85]})
        ruta_mesh = len(meshes)
        meshes.append(crear_ruta(generador,inicio))
        arco = len(nodos)
        nodos.append({"name":f"Arco de ruta {indice+1}","mesh":ruta_mesh})
        nodos[padre]["children"] = [trayectoria,arco]
        for etiqueta, progreso in (("Origen",0),("Destino",1)):
            punto = punto_ruta(progreso,inicio)
            punto = tuple(v*1.008/1.055 for v in punto)
            nodos[padre]["children"].append(len(nodos))
            nodos.append({"name":f"{etiqueta} ruta {indice+1}","mesh":3,"translation":punto})
        entrada = generador.agregar_accesor(tiempos,"SCALAR",COMPONENTE_FLOAT,limites=True)
        for propiedad, valores, tipo in (("translation",posiciones,"VEC3"),("rotation",orientaciones,"VEC4")):
            salida = generador.agregar_accesor(valores,tipo,COMPONENTE_FLOAT)
            muestreadores.append({"input":entrada,"output":salida,"interpolation":"LINEAR"})
            canales.append({"sampler":len(muestreadores)-1,"target":{"node":trayectoria,"path":propiedad}})

    indice_vista_textura = generador.agregar_imagen_png(RUTA_TEXTURA)
    materiales = [
        {"name": "Mapa Natural Earth", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.04, "roughnessFactor": 0.72}},
        {"name": "Resplandor atmosferico", "alphaMode": "BLEND", "doubleSided": True, "emissiveFactor": [0.08, 0.65, 1.0], "pbrMetallicRoughness": {"baseColorFactor": [0.10, 0.63, 0.95, 0.18], "metallicFactor": 0.0, "roughnessFactor": 0.32}},
        {"name": "Fuselaje marfil", "pbrMetallicRoughness": {"baseColorFactor": [0.91, 0.97, 1.0, 1.0], "metallicFactor": 0.52, "roughnessFactor": 0.28}},
        {"name": "Alas cian", "pbrMetallicRoughness": {"baseColorFactor": [0.12, 0.78, 0.94, 1.0], "metallicFactor": 0.45, "roughnessFactor": 0.3}},
        {"name": "Ruta luminosa", "alphaMode": "BLEND", "doubleSided": True, "emissiveFactor": [0.02, 0.3, 0.46], "pbrMetallicRoughness": {"baseColorFactor": [0.06, 0.46, 0.62, 0.28], "metallicFactor": 0.1, "roughnessFactor": 0.42}},
    ]
    materiales.append({"name":"Cabina, ventanas y turbinas", "pbrMetallicRoughness":{"baseColorFactor":[.025,.08,.14,1],"metallicFactor":.3,"roughnessFactor":.3}})
    gltf = {
        "asset": {"version": "2.0", "generator": "Generador original AeroTech"},
        "scene": 0,
        "scenes": [{"name": "Globo de AeroTech", "nodes": [0]}],
        "nodes": nodos,
        "meshes": meshes,
        "materials": materiales,
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"name": "Mapa mundial Natural Earth", "bufferView": indice_vista_textura, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 33071}],
        "animations": [{"name": "Orbitas de vuelos", "samplers": muestreadores, "channels": canales}],
    }
    return generador, gltf


def main() -> None:
    generador, gltf = crear_escena()
    generador.guardar(gltf, RUTA_MODELO)
    print(f"Modelo generado: {RUTA_MODELO} ({RUTA_MODELO.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
