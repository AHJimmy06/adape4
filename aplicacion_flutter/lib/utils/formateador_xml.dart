/// Indenta XML de elementos sin volver a serializar ni decodificar su contenido.
/// Ante contenido mixto o declaraciones complejas conserva el documento original.
String formatearXml(String xml) {
  if (xml.contains(RegExp(r'xml:space\s*=')) || xml.contains('<!DOCTYPE')) {
    return xml;
  }
  final tokens = _tokensXml(xml);
  if (tokens == null) return xml;
  final pila = <_ElementoXml>[];
  for (final token in tokens) {
    if (_esApertura(token)) {
      if (pila.isNotEmpty) pila.last.tieneElementos = true;
      if (!token.endsWith('/>')) {
        pila.add(_ElementoXml(_nombre(token)));
      }
    } else if (token.startsWith('</')) {
      if (pila.isEmpty || pila.last.nombre != _nombre(token)) return xml;
      final elemento = pila.removeLast();
      if (elemento.tieneTexto && elemento.tieneElementos) return xml;
    } else if (!token.startsWith('<') || token.startsWith('<![CDATA[')) {
      if (pila.isNotEmpty && token.trim().isNotEmpty) {
        pila.last.tieneTexto = true;
      }
    } else if (pila.isNotEmpty) {
      pila.last.tieneElementos = true;
    }
  }
  if (pila.isNotEmpty) return xml;

  final lineas = <String>[];
  var nivel = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (!token.startsWith('<')) {
      if (token.trim().isNotEmpty) return xml;
      continue;
    }
    if (token.startsWith('</')) nivel--;
    if (nivel < 0) return xml;
    var linea = '${'  ' * nivel}$token';
    if (_esApertura(token) && !token.endsWith('/>')) {
      // Conserva el valor de un elemento hoja en una sola línea, incluso CDATA.
      var fin = i + 1;
      while (fin < tokens.length &&
          (!tokens[fin].startsWith('<') ||
              tokens[fin].startsWith('<![CDATA['))) {
        fin++;
      }
      if (fin < tokens.length && tokens[fin].startsWith('</')) {
        linea += tokens.sublist(i + 1, fin + 1).join();
        i = fin;
      } else {
        nivel++;
      }
    }
    lineas.add(linea);
  }
  return lineas.join('\n');
}

bool _esApertura(String token) =>
    token.startsWith('<') &&
    !token.startsWith('</') &&
    !token.startsWith('<?') &&
    !token.startsWith('<!');

String _nombre(String token) =>
    token.replaceFirst(RegExp(r'^</?'), '').split(RegExp(r'[\s/>]')).first;

class _ElementoXml {
  _ElementoXml(this.nombre);
  final String nombre;
  bool tieneTexto = false;
  bool tieneElementos = false;
}

List<String>? _tokensXml(String xml) {
  final tokens = <String>[];
  var inicio = 0;
  while (inicio < xml.length) {
    if (xml[inicio] != '<') {
      final siguiente = xml.indexOf('<', inicio);
      final fin = siguiente < 0 ? xml.length : siguiente;
      tokens.add(xml.substring(inicio, fin));
      inicio = fin;
      continue;
    }
    String? terminador;
    if (xml.startsWith('<!--', inicio)) terminador = '-->';
    if (xml.startsWith('<![CDATA[', inicio)) terminador = ']]>';
    if (xml.startsWith('<?', inicio)) terminador = '?>';
    if (terminador != null) {
      final fin = xml.indexOf(terminador, inicio + 2);
      if (fin < 0) return null;
      tokens.add(xml.substring(inicio, fin + terminador.length));
      inicio = fin + terminador.length;
      continue;
    }
    String? comilla;
    var fin = inicio + 1;
    for (; fin < xml.length; fin++) {
      final caracter = xml[fin];
      if (comilla != null) {
        if (caracter == comilla) comilla = null;
      } else if (caracter == '"' || caracter == "'") {
        comilla = caracter;
      } else if (caracter == '>') {
        break;
      }
    }
    if (fin == xml.length) return null;
    tokens.add(xml.substring(inicio, fin + 1));
    inicio = fin + 1;
  }
  return tokens;
}
