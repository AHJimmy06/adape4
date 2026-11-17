/// Geographic catalog is deliberately separate from exact country comparison.
typedef GeoPoint = (double latitude, double longitude);

class RutaVuelo {
  RutaVuelo(this.origen, this.destino);
  final String origen;
  final String destino;

  static const ciudades = <String, (String, GeoPoint)>{
    'quito': ('Ecuador', (-0.18, -78.47)),
    // Referencia aproximada del cantón: manual oficial de Gestión de Riesgos.
    // https://www.gestionderiesgos.gob.ec/wp-content/uploads/downloads/2020/12/RESOLUCION-DE-INSTITUCIONALIZACION-MANUAL-TECNICO-PREPARACION-DEAGENDAS-DE-REDUCCION-DE-RIEGOS_compressed.pdf
    'ambato': ('Ecuador', (-1.224444, -78.619722)),
    'guayaquil': ('Ecuador', (-2.17, -79.92)),
    'cuenca': ('Ecuador', (-2.90, -79.00)),
    'manta': ('Ecuador', (-0.97, -80.71)),
    'loja': ('Ecuador', (-3.99, -79.20)),
    'esmeraldas': ('Ecuador', (0.96, -79.65)),
    'lima': ('Perú', (-12.05, -77.04)),
    'bogotá': ('Colombia', (4.71, -74.07)),
    'bogota': ('Colombia', (4.71, -74.07)),
    'miami': ('USA', (25.76, -80.19)),
    'madrid': ('España', (40.42, -3.70)),
  };
  static const paises = <String, GeoPoint>{
    'Ecuador': (-1.8, -78.2),
    'Peru': (-9.2, -75),
    'Colombia': (4, -73),
    'USA': (39, -98),
    'Spain': (40, -4),
    'Mexico': (23, -102),
    'Argentina': (-35, -64),
    'Brazil': (-10, -53),
    'Chile': (-33, -71),
    'Canada': (56, -106),
    'France': (47, 2),
    'UK': (54, -2),
    'Germany': (51, 10),
    'Japan': (37, 138),
  };
  static String? clavePais(String? value) {
    if (value == null) return null;
    return const {
      'ecuador': 'Ecuador',
      'perú': 'Peru',
      'peru': 'Peru',
      'colombia': 'Colombia',
      'usa': 'USA',
      'estados unidos': 'USA',
      'united states': 'USA',
      'united states of america': 'USA',
      'ee. uu.': 'USA',
      'españa': 'Spain',
      'spain': 'Spain',
      'méxico': 'Mexico',
      'mexico': 'Mexico',
      'argentina': 'Argentina',
      'brasil': 'Brazil',
      'brazil': 'Brazil',
      'chile': 'Chile',
      'canadá': 'Canada',
      'canada': 'Canada',
      'francia': 'France',
      'france': 'France',
      'reino unido': 'UK',
      'uk': 'UK',
      'alemania': 'Germany',
      'germany': 'Germany',
      'japón': 'Japan',
      'japan': 'Japan',
    }[value.trim().toLowerCase()];
  }

  static String ciudad(String value) => value.split(',').first.trim();
  static String? _pais(String value) {
    final comma = value.indexOf(',');
    if (comma < 0) return ciudades[value.trim().toLowerCase()]?.$1;
    final country = value.substring(comma + 1).trim();
    return country.isEmpty ? null : country;
  }

  String? get paisOrigen => _pais(origen);
  String? get paisDestino => _pais(destino);
  bool get esNacional => paisOrigen != null && paisOrigen == paisDestino;
  bool get esInternacional =>
      paisOrigen != null && paisDestino != null && !esNacional;
  GeoPoint? get centroOrigen => paises[clavePais(paisOrigen)];
  GeoPoint? get centroDestino => paises[clavePais(paisDestino)];
  GeoPoint? _punto(String value, String? country) {
    final entry = ciudades[ciudad(value).toLowerCase()];
    return entry != null && clavePais(entry.$1) == clavePais(country)
        ? entry.$2
        : null;
  }

  GeoPoint? get puntoOrigen => _punto(origen, paisOrigen);
  GeoPoint? get puntoDestino => _punto(destino, paisDestino);
}
