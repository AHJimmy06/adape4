class Usuario {
  const Usuario({required this.id, required this.nombre, required this.correo});

  final int? id;
  final String nombre;
  final String correo;

  factory Usuario.fromJson(Map<String, dynamic> json) {
    final identificador = json['id'];
    return Usuario(
      id: identificador is num ? identificador.toInt() : null,
      nombre: json['nombre'] as String? ?? '',
      correo: json['correo'] as String? ?? '',
    );
  }
}
