import 'vuelo.dart';

class Reserva {
  const Reserva({
    required this.id,
    required this.vueloId,
    required this.cantidad,
    required this.subtotal,
    required this.iva,
    required this.porcentajeIva,
    required this.total,
    required this.estado,
    required this.fechaReserva,
    this.vuelo,
  });

  final String id;
  final String vueloId;
  final int cantidad;
  final double subtotal;
  final double iva;
  final double porcentajeIva;
  final double total;
  final String estado;
  final String fechaReserva;
  final Vuelo? vuelo;

  factory Reserva.fromJson(Map<String, dynamic> json) {
    final vueloJson = json['vuelo'];
    return Reserva(
      id: json['id'].toString(),
      vueloId: json['vuelo_id'].toString(),
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 1,
      subtotal: (json['subtotal'] as num).toDouble(),
      iva: (json['iva'] as num).toDouble(),
      porcentajeIva: (json['porcentaje_iva'] as num).toDouble(),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      estado: json['estado'] as String? ?? 'confirmada',
      fechaReserva:
          json['creado_en'] as String? ??
          json['fecha_reserva'] as String? ??
          '',
      vuelo: vueloJson is Map<String, dynamic>
          ? Vuelo.fromJson(vueloJson)
          : null,
    );
  }
}
