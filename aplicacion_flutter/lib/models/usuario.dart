class Usuario {
  const Usuario({
    required this.id,
    required this.nombre,
    required this.correo,
    this.rol = 'USER',
    this.activo = true,
  });

  final String id;
  final String nombre;
  final String correo;
  final String rol;
  final bool activo;
  bool get esAdministrador => rol == 'ADMIN';

  factory Usuario.fromJson(Map<String, dynamic> json) => Usuario(
    id: json['id']?.toString() ?? '',
    nombre: json['nombre'] as String? ?? '',
    correo: json['correo'] as String? ?? '',
    rol: json['rol'] == 'ADMIN' ? 'ADMIN' : 'USER',
    activo: json['activo'] != false,
  );
}
