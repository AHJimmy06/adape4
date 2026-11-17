import 'dart:io';
import 'dart:typed_data';

class ModeloRutaArchivo {
  ModeloRutaArchivo._(this.src, this._file, this._directory);
  final String src;
  final File _file;
  final Directory _directory;
  static Future<ModeloRutaArchivo> crear(Uint8List bytes) async {
    final directory = await Directory.systemTemp.createTemp('aerotech-route-');
    final file = File('${directory.path}/route.glb');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return ModeloRutaArchivo._(file.uri.toString(), file, directory);
    } catch (_) {
      if (await file.exists()) await file.delete();
      await directory.delete();
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (await _file.exists()) await _file.delete();
    if (await _directory.exists()) await _directory.delete();
  }
}
