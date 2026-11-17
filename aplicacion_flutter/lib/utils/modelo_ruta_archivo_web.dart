import 'dart:convert';
import 'dart:typed_data';

class ModeloRutaArchivo {
  ModeloRutaArchivo._(this.src);
  final String src;
  static Future<ModeloRutaArchivo> crear(Uint8List bytes) async =>
      ModeloRutaArchivo._(
        'data:model/gltf-binary;base64,${base64Encode(bytes)}',
      );
  Future<void> dispose() async {}
}
