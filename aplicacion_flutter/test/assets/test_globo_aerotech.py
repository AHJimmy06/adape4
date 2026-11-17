"""Verifica la estructura mínima de la escena 3D incluida en AeroTech."""

import json
import math
import struct
import unittest
from pathlib import Path


MODELO = Path(__file__).parents[2] / "assets" / "models" / "aerotech_globo.glb"


class GloboAerotechTest(unittest.TestCase):
    def test_modelo_glb_incluye_planeta_aviones_y_animacion_orbital(self):
        contenido = MODELO.read_bytes()

        magia, version, longitud = struct.unpack_from("<4sII", contenido)
        self.assertEqual(magia, b"glTF")
        self.assertEqual(version, 2)
        self.assertEqual(longitud, len(contenido))

        longitud_json, tipo_json = struct.unpack_from("<I4s", contenido, 12)
        self.assertEqual(tipo_json, b"JSON")
        gltf = json.loads(contenido[20 : 20 + longitud_json].decode("utf-8"))
        inicio_binario = 20 + longitud_json
        longitud_binaria, tipo_binario = struct.unpack_from("<I4s", contenido, inicio_binario)
        self.assertEqual(tipo_binario, b"BIN\0")
        self.assertEqual(inicio_binario + 8 + longitud_binaria, len(contenido))

        for vista in gltf["bufferViews"]:
            self.assertLessEqual(vista["byteOffset"] + vista["byteLength"], longitud_binaria)
        for accesor in gltf["accessors"]:
            self.assertLess(accesor["bufferView"], len(gltf["bufferViews"]))

        nodos = gltf["nodes"]
        visitados = set()

        def visitar(indice):
            self.assertNotIn(indice, visitados)
            visitados.add(indice)
            for hijo in nodos[indice].get("children", []):
                visitar(hijo)

        for raiz in gltf["scenes"][gltf["scene"]]["nodes"]:
            visitar(raiz)
        self.assertEqual(visitados, set(range(len(nodos))))

        indice_posiciones_planeta = gltf["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
        cantidad_vertices = gltf["accessors"][indice_posiciones_planeta]["count"]
        self.assertGreater(cantidad_vertices, 70_000)

        atributos_planeta = gltf["meshes"][0]["primitives"][0]["attributes"]
        indice_uv = atributos_planeta["TEXCOORD_0"]
        accessor_uv = gltf["accessors"][indice_uv]
        self.assertEqual(accessor_uv["type"], "VEC2")
        self.assertEqual(accessor_uv["count"], cantidad_vertices)
        vista_uv = gltf["bufferViews"][accessor_uv["bufferView"]]
        inicio_uv = (
            inicio_binario
            + 8
            + vista_uv.get("byteOffset", 0)
            + accessor_uv.get("byteOffset", 0)
        )
        v_sur = struct.unpack_from("<2f", contenido, inicio_uv)[1]
        v_norte = struct.unpack_from(
            "<2f", contenido, inicio_uv + (accessor_uv["count"] - 1) * 8
        )[1]
        self.assertAlmostEqual(v_sur, 1.0)
        self.assertAlmostEqual(v_norte, 0.0)

        material_planeta = gltf["materials"][gltf["meshes"][0]["primitives"][0]["material"]]
        indice_textura = material_planeta["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        imagen = gltf["images"][gltf["textures"][indice_textura]["source"]]
        self.assertEqual(imagen["mimeType"], "image/png")
        vista_imagen = gltf["bufferViews"][imagen["bufferView"]]
        bytes_imagen = contenido[
            inicio_binario + 8 + vista_imagen["byteOffset"]:
            inicio_binario + 8 + vista_imagen["byteOffset"] + vista_imagen["byteLength"]
        ]
        self.assertTrue(bytes_imagen.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertGreater(struct.unpack_from(">I", bytes_imagen, 16)[0], 1_000)
        self.assertGreater(struct.unpack_from(">I", bytes_imagen, 20)[0], 500)

        nombres = {nodo.get("name") for nodo in gltf["nodes"]}
        self.assertIn("Planeta AeroTech", nombres)
        aviones = [n for n in nodos if n.get("name", "").startswith("Avion de ruta ")]
        rutas = [n for n in nodos if n.get("name", "").startswith("Trayectoria ")]
        self.assertEqual(len(aviones), 2)
        self.assertEqual(len(rutas), 2)

        def leer_accesor(indice):
            accesor = gltf["accessors"][indice]
            vista = gltf["bufferViews"][accesor["bufferView"]]
            ancho = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accesor["type"]]
            inicio = inicio_binario + 8 + vista["byteOffset"]
            return [struct.unpack_from("<" + "f" * ancho, contenido, inicio + i * ancho * 4)
                    for i in range(accesor["count"])]

        animacion = gltf["animations"][0]
        self.assertEqual(len(animacion["channels"]), 4)
        posiciones_por_ruta = []
        for ruta in rutas:
            canales = {c["target"]["path"]: c for c in animacion["channels"]
                       if c["target"]["node"] == nodos.index(ruta)}
            posiciones = leer_accesor(animacion["samplers"][canales["translation"]["sampler"]]["output"])
            rotaciones = leer_accesor(animacion["samplers"][canales["rotation"]["sampler"]]["output"])
            posiciones_por_ruta.append(posiciones)
            self.assertAlmostEqual(math.dist(posiciones[0], (0, 0, 0)), 1.055, places=5)
            self.assertAlmostEqual(math.dist(posiciones[112], (0, 0, 0)), 1.055, places=5)
            self.assertGreater(math.dist(posiciones[56], (0, 0, 0)), 1.35)
            self.assertGreater(math.dist(posiciones[0], posiciones[112]), 1.0)
            self.assertLess(math.dist(posiciones[0], posiciones[-1]), 1e-6)
            self.assertAlmostEqual(abs(sum(a*b for a,b in zip(rotaciones[0], rotaciones[-1]))), 1, places=5)
            for i in list(range(1, 111)) + list(range(129, 239)):
                velocidad = [b-a for a,b in zip(posiciones[i-1], posiciones[i+1])]
                longitud = math.sqrt(sum(v*v for v in velocidad))
                x, y, z, w = rotaciones[i]
                nariz = (-2*(x*z+w*y), -2*(y*z-w*x), -(1-2*(x*x+y*y)))
                self.assertGreater(sum(a*b/longitud for a,b in zip(nariz,velocidad)), 0.995)
        # Verifica separacion global incluso entre instantes distintos.
        globales = []
        for ruta, posiciones in zip(rutas,posiciones_por_ruta):
            padre = next(n for n in nodos if nodos.index(ruta) in n.get("children",[]))
            _,_,z,w = padre["rotation"]
            coseno, seno = 1-2*z*z, 2*z*w
            globales.append([(coseno*x-seno*y,seno*x+coseno*y,zeta) for x,y,zeta in posiciones])
        self.assertGreater(min(math.dist(a,b) for a in globales[0] for b in globales[1]), 1.0)
        # Ambas rutas estan en lados distintos: no comparten origen ni destino.
        for nodo in rutas:
            self.assertEqual(len(nodo["children"]), 1)
        partes = gltf["meshes"][2]["primitives"]
        self.assertGreaterEqual(len(partes), 6)
        self.assertTrue(all(gltf["accessors"][p["attributes"]["POSITION"]]["count"] >= 24 for p in partes))


if __name__ == "__main__":
    unittest.main()
