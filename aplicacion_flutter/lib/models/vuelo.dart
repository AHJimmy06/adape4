class Vuelo {
  const Vuelo({
    required this.id,
    required this.origen,
    required this.destino,
    required this.fecha,
    required this.horaSalida,
    required this.horaLlegada,
    required this.precio,
    required this.asientosDisponibles,
    this.version = 1,
    this.tieneReservas = false,
  });

  final String id;
  final String origen;
  final String destino;
  final String fecha;
  final String horaSalida;
  final String horaLlegada;
  final double precio;
  final int asientosDisponibles;
  final int version;
  final bool tieneReservas;

  factory Vuelo.fromJson(Map<String, dynamic> json) {
    return Vuelo(
      id: json['id'].toString(),
      origen: json['origen'] as String,
      destino: json['destino'] as String,
      fecha: json['fecha'] as String,
      horaSalida: json['hora_salida'] as String? ?? '',
      horaLlegada: json['hora_llegada'] as String? ?? '',
      precio: (json['precio'] as num).toDouble(),
      asientosDisponibles: (json['asientos_disponibles'] as num).toInt(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      tieneReservas: json['tiene_reservas'] == true,
    );
  }
}
