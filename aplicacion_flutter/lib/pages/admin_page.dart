import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/usuario.dart';
import '../models/vuelo.dart';
import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _form = GlobalKey<FormState>();
  final _desplazamiento = ScrollController();
  final _fields = List.generate(7, (_) => TextEditingController());
  List<Usuario> _usuarios = [];
  List<Vuelo> _vuelos = [];
  Vuelo? _editando;
  bool _ocupado = false;
  bool _mostrandoConflicto = false;
  bool _accesoDenegado = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    if (widget.apiService.esAdministrador) _cargarDatos();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    _desplazamiento.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      await accion();
    } catch (error) {
      if (!mounted) return;
      if (error is ExcepcionApi &&
          (error.codigoError == 'vuelo_modificado' ||
              error.codigoError == 'vuelo_con_reservas' ||
              error.codigoError == 'vuelo_no_encontrado')) {
        await _resolverConflicto(error);
        return;
      }
      if (mounted) {
        setState(() {
          _mensaje = error is ExcepcionApi
              ? error.mensaje
              : 'No se pudo completar la operación. Inténtalo nuevamente.';
          if (error is ExcepcionApi &&
              (error.codigo == 401 || error.codigo == 403)) {
            _accesoDenegado = true;
            _usuarios = [];
            _vuelos = [];
            _editando = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _refrescarVuelos() async {
    final vuelos = await widget.apiService.buscarVuelos();
    if (mounted) setState(() => _vuelos = vuelos);
  }

  Future<void> _cargarDatos() => _ejecutar(() async {
    final usuarios = await widget.apiService.listarUsuarios();
    if (mounted) setState(() => _usuarios = usuarios);
    await _refrescarVuelos();
  });

  Future<void> _resolverConflicto(ExcepcionApi error) async {
    final reservado = error.codigoError == 'vuelo_con_reservas';
    setState(() => _mostrandoConflicto = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (contexto) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            reservado ? 'Vuelo con reservas' : 'El vuelo cambió',
          ),
          content: Text(
            reservado
                ? 'Este vuelo tiene reservas activas y no puede modificarse ni eliminarse. '
                      'Al aceptar actualizaremos la lista.'
                : 'Otra operación modificó o retiró este vuelo. '
                      'Al aceptar cargaremos los datos actuales. '
                      'Si quieres editarlo, selecciónalo nuevamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _mostrandoConflicto = false);
    _cancelarEdicion();
    try {
      await _refrescarVuelos();
    } catch (_) {
      if (mounted) {
        setState(
          () => _mensaje = 'No se pudo actualizar la lista. Pulsa Actualizar vuelos para reintentar.',
        );
      }
    }
  }

  Future<void> _cargarUsuarios() => _ejecutar(() async {
    final usuarios = await widget.apiService.listarUsuarios();
    if (mounted) setState(() => _usuarios = usuarios);
  });

  Future<void> _actualizarPerfil() => _ejecutar(() async {
    await widget.apiService.obtenerPerfil();
    final usuarios = widget.apiService.esAdministrador
        ? await widget.apiService.listarUsuarios()
        : <Usuario>[];
    if (mounted) {
      setState(() {
        _usuarios = usuarios;
        _accesoDenegado = false;
        if (!widget.apiService.esAdministrador) {
          _vuelos = [];
          _editando = null;
        }
      });
    }
    if (widget.apiService.esAdministrador) await _refrescarVuelos();
  });

  Future<void> _promover(Usuario usuario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Convertir en administrador?'),
        content: Text(
          '${usuario.nombre} podrá crear vuelos y promover a otros usuarios. Esta pantalla no permite revertir el cambio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _ejecutar(() async {
      final actualizado = await widget.apiService.promoverUsuario(usuario.id);
      if (mounted) {
        setState(() {
          _usuarios = _usuarios
              .map((u) => u.id == actualizado.id ? actualizado : u)
              .toList();
          _mensaje = 'Usuario actualizado a ADMIN.';
        });
      }
    });
  }

  void _editarVuelo(Vuelo vuelo) {
    if (vuelo.tieneReservas) return;
    if (_ocupado) return;
    final valores = [
      vuelo.origen,
      vuelo.destino,
      vuelo.fecha,
      vuelo.horaSalida.length >= 5
          ? vuelo.horaSalida.substring(0, 5)
          : vuelo.horaSalida,
      vuelo.horaLlegada.length >= 5
          ? vuelo.horaLlegada.substring(0, 5)
          : vuelo.horaLlegada,
      vuelo.precio.toStringAsFixed(2),
      vuelo.asientosDisponibles.toString(),
    ];
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].text = valores[i];
    }
    setState(() {
      _editando = vuelo;
      _mensaje = null;
    });
    if (_desplazamiento.hasClients) {
      _desplazamiento.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _cancelarEdicion() {
    for (final campo in _fields) {
      campo.clear();
    }
    setState(() {
      _editando = null;
      _mensaje = null;
    });
  }

  Future<void> _crearVuelo() async {
    if (_ocupado || !_form.currentState!.validate()) return;
    final editando = _editando;
    await _ejecutar(() async {
      final origen = _fields[0].text.split(',').map((s) => s.trim()).join(', ');
      final destino = _fields[1].text
          .split(',')
          .map((s) => s.trim())
          .join(', ');
      final fecha = _fields[2].text.trim();
      final salida = _fields[3].text.trim();
      final llegada = _fields[4].text.trim();
      final precio = double.parse(_fields[5].text.trim());
      final asientos = int.parse(_fields[6].text.trim());
      if (editando == null) {
        await widget.apiService.crearVuelo(
          origen: origen,
          destino: destino,
          fecha: fecha,
          horaSalida: salida,
          horaLlegada: llegada,
          precio: precio,
          asientosDisponibles: asientos,
        );
      } else {
        await widget.apiService.actualizarVuelo(
          id: editando.id,
          version: editando.version,
          origen: origen,
          destino: destino,
          fecha: fecha,
          horaSalida: salida,
          horaLlegada: llegada,
          precio: precio,
          asientosDisponibles: asientos,
        );
      }
      if (!mounted) return;
      _cancelarEdicion();
      await _refrescarVuelos();
      if (mounted) {
        setState(
          () => _mensaje = editando == null
              ? 'Vuelo creado correctamente.'
              : 'Vuelo actualizado correctamente.',
        );
      }
    });
  }

  Future<void> _eliminarVuelo(Vuelo vuelo) async {
    if (_ocupado || vuelo.tieneReservas) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Eliminar este vuelo?'),
        content: Text(
          '${vuelo.origen} → ${vuelo.destino}\n'
          'Solo se eliminará si no tiene reservas activas. '
          'El historial de reservas canceladas se conservará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Eliminar vuelo'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _ejecutar(() async {
      await widget.apiService.eliminarVuelo(vuelo.id, version: vuelo.version);
      if (!mounted) return;
      if (_editando?.id == vuelo.id) _cancelarEdicion();
      await _refrescarVuelos();
      if (mounted) setState(() => _mensaje = 'Vuelo eliminado correctamente.');
    });
  }

  DateTime get _manana {
    final ahora = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    return DateTime(ahora.year, ahora.month, ahora.day + 1);
  }

  void _revalidar() {
    if (mounted) setState(() => _mensaje = null);
    _form.currentState?.validate();
  }

  Future<void> _elegirFecha() async {
    final primera = _manana;
    final actual = DateTime.tryParse(_fields[2].text);
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual != null && !actual.isBefore(primera)
          ? actual
          : primera,
      firstDate: primera,
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Selecciona la fecha del vuelo',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (elegida == null || !mounted) return;
    _fields[2].text =
        '${elegida.year.toString().padLeft(4, '0')}-${elegida.month.toString().padLeft(2, '0')}-${elegida.day.toString().padLeft(2, '0')}';
    _revalidar();
  }

  List<TextInputFormatter>? _formatos(int index) {
    if (index == 5) {
      return [
        TextInputFormatter.withFunction((anterior, nuevo) {
          final texto = nuevo.text;
          if (texto.isEmpty) return nuevo;
          final numero = double.tryParse(texto);
          return RegExp(r'^[0-9]+(?:\.[0-9]{0,2})?$').hasMatch(texto) &&
                  numero != null &&
                  numero <= 99999999.99
              ? nuevo
              : anterior;
        }),
      ];
    }
    if (index == 6) {
      return [
        TextInputFormatter.withFunction((anterior, nuevo) {
          if (nuevo.text.isEmpty) return nuevo;
          final numero = int.tryParse(nuevo.text);
          return RegExp(r'^[0-9]+$').hasMatch(nuevo.text) &&
                  numero != null &&
                  numero <= 2147483647
              ? nuevo
              : anterior;
        }),
      ];
    }
    return null;
  }

  String? _validar(int index, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Campo obligatorio.';
    if (index < 2) {
      final parts = text.split(',');
      if (text.runes.length > 240 ||
          parts.length != 2 ||
          parts.any((part) => part.trim().isEmpty)) {
        return 'Usa el formato Ciudad, País (máximo 240 caracteres).';
      }
      String ruta(String valor) =>
          valor.split(',').map((p) => p.trim().toLowerCase()).join(',');
      if (_fields[0].text.isNotEmpty &&
          _fields[1].text.isNotEmpty &&
          ruta(_fields[0].text) == ruta(_fields[1].text)) {
        return 'Origen y destino deben ser distintos.';
      }
    }
    if (index == 2) {
      final date = DateTime.tryParse(text);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != text) {
        return 'Selecciona una fecha válida en el calendario.';
      }
      if (date.isBefore(_manana)) {
        return 'Selecciona una fecha posterior a hoy.';
      }
    }
    if (index == 3 || index == 4) {
      final hora = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
      if (!hora.hasMatch(text)) return 'Usa una hora válida HH:MM.';
      final salida = _fields[3].text.trim();
      final llegada = _fields[4].text.trim();
      if (hora.hasMatch(salida) &&
          hora.hasMatch(llegada) &&
          llegada.compareTo(salida) <= 0) {
        return 'La llegada debe ser posterior a la salida.';
      }
    }
    if (index == 5) {
      final price = double.tryParse(text);
      if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(text) ||
          price == null ||
          !price.isFinite ||
          price < 0 ||
          price > 99999999.99) {
        return 'Precio entre 0 y 99999999.99, con hasta dos decimales.';
      }
    }
    if (index == 6 &&
        (int.tryParse(text) == null ||
            int.parse(text) < (_editando == null ? 1 : 0) ||
            int.parse(text) > 2147483647)) {
      return _editando == null
          ? 'Ingresa entre 1 y 2147483647 asientos.'
          : 'Ingresa entre 0 y 2147483647 asientos restantes.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final autorizado = widget.apiService.esAdministrador && !_accesoDenegado;
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _desplazamiento,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : _actualizarPerfil,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar perfil'),
                  ),
                  if (_ocupado && !_mostrandoConflicto)
                    const LinearProgressIndicator(),
                  if (_mensaje != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _mensaje!,
                        key: const ValueKey('admin-message'),
                      ),
                    ),
                  if (!autorizado)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Acceso exclusivo para administradores.'),
                    ),
                  if (autorizado) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _form,
                          autovalidateMode: AutovalidateMode.always,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _editando == null
                                    ? 'Crear vuelo'
                                    : 'Editar vuelo',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AerotechTheme.navy,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (final (index, label) in [
                                'Origen (Ciudad, País)',
                                'Destino (Ciudad, País)',
                                'Fecha (AAAA-MM-DD)',
                                'Salida (HH:MM)',
                                'Llegada (HH:MM)',
                                'Precio (USD)',
                                _editando == null
                                    ? 'Asientos disponibles'
                                    : 'Asientos restantes disponibles',
                              ].indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: TextFormField(
                                    key: ValueKey('flight-field-$index'),
                                    controller: _fields[index],
                                    enabled: !_ocupado,
                                    readOnly: index == 2,
                                    onTap: index == 2 ? _elegirFecha : null,
                                    onChanged: (_) => _revalidar(),
                                    inputFormatters: _formatos(index),
                                    decoration: InputDecoration(
                                      labelText: label,
                                      errorMaxLines: 3,
                                      suffixIcon: index == 2
                                          ? IconButton(
                                              tooltip: 'Elegir fecha',
                                              icon: const Icon(
                                                Icons.calendar_month,
                                              ),
                                              onPressed: _ocupado
                                                  ? null
                                                  : _elegirFecha,
                                            )
                                          : null,
                                    ),
                                    keyboardType: index >= 5
                                        ? TextInputType.numberWithOptions(
                                            decimal: index == 5,
                                          )
                                        : TextInputType.text,
                                    validator: (value) =>
                                        _validar(index, value),
                                  ),
                                ),
                              FilledButton.icon(
                                onPressed: _ocupado ? null : _crearVuelo,
                                icon: const Icon(Icons.add),
                                label: Text(
                                  _editando == null
                                      ? 'Guardar vuelo'
                                      : 'Guardar cambios',
                                ),
                              ),
                              if (_editando != null)
                                TextButton(
                                  onPressed: _ocupado ? null : _cancelarEdicion,
                                  child: const Text('Cancelar edición'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Vuelos publicados',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _ocupado
                              ? null
                              : () => _ejecutar(_refrescarVuelos),
                          tooltip: 'Actualizar vuelos',
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const Text(
                      'Administra las rutas y su disponibilidad actual.',
                    ),
                    if (_vuelos.isEmpty && !_ocupado)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No hay vuelos publicados.'),
                      ),
                    for (final vuelo in _vuelos)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${vuelo.origen} → ${vuelo.destino}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${vuelo.fecha} · ${vuelo.horaSalida} — ${vuelo.horaLlegada}',
                              ),
                              Text(
                                'USD ${vuelo.precio.toStringAsFixed(2)} · '
                                '${vuelo.asientosDisponibles} asientos restantes',
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    key: ValueKey('edit-flight-${vuelo.id}'),
                                    onPressed: _ocupado || vuelo.tieneReservas
                                        ? null
                                        : () => _editarVuelo(vuelo),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Editar'),
                                  ),
                                  TextButton.icon(
                                    key: ValueKey('delete-flight-${vuelo.id}'),
                                    onPressed: _ocupado || vuelo.tieneReservas
                                        ? null
                                        : () => _eliminarVuelo(vuelo),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Usuarios registrados',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: _ocupado ? null : _cargarUsuarios,
                          tooltip: 'Actualizar usuarios',
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (_usuarios.isEmpty && !_ocupado)
                      const Text('No hay usuarios para mostrar.'),
                    for (final usuario in _usuarios)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                usuario.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(usuario.correo),
                              Text(usuario.rol),
                              if (!usuario.esAdministrador)
                                TextButton.icon(
                                  onPressed: _ocupado
                                      ? null
                                      : () => _promover(usuario),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: const Text(
                                    'Convertir en administrador',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
