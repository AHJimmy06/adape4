import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../theme/aerotech_theme.dart';
import '../widgets/sistema_admin/formulario_operacion.dart';

class SistemaAdminPage extends StatefulWidget {
  const SistemaAdminPage({super.key, required this.apiService});
  final ApiService apiService;
  @override
  State<SistemaAdminPage> createState() => _SistemaAdminPageState();
}

class _SistemaAdminPageState extends State<SistemaAdminPage> {
  static const _recursos = ['aeropuertos', 'aviones', 'rutas', 'vuelos'];
  static const _titulos = [
    'Aeropuertos',
    'Aviones',
    'Rutas',
    'Vuelos',
    'Usuarios',
  ];
  static const _iconos = [
    Icons.local_airport,
    Icons.airplanemode_active,
    Icons.route,
    Icons.flight_takeoff,
    Icons.people_outline,
  ];
  final Map<String, List<Registro>> _catalogos = {};
  List<Usuario> _usuarios = [];
  int _indice = 0;
  bool _cargando = false, _mutando = false, _denegado = false;
  String? _error;
  late final SistemaApi _api = SistemaApi(widget.apiService);
  @override
  void initState() {
    super.initState();
    if (widget.apiService.esAdministrador) _cargar();
  }

  Future<void> _cargar() async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait(
        _recursos.map(
          (r) => _api.lista(
            '/$r',
            r,
            parametros: r == 'vuelos' ? {'admin': 'true'} : null,
          ),
        ),
      );
      final usuarios = await widget.apiService.listarUsuarios();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _recursos.length; i++) {
          _catalogos[_recursos[i]] = resultados[i];
        }
        _usuarios = usuarios;
      });
    } catch (e) {
      if (mounted) _mostrarError(e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(Object e) {
    setState(() {
      _error = e is ExcepcionApi
          ? e.mensaje
          : 'No se pudo conectar. Reintenta la operación.';
      if (e is ExcepcionApi && (e.codigo == 401 || e.codigo == 403)) {
        _denegado = true;
        _catalogos.clear();
        _usuarios = [];
      }
    });
  }

  bool bloqueado(Registro r) =>
      r['tiene_reservas'] == true || r['bloqueado'] == true;
  String motivo(Registro r) =>
      r['motivo_bloqueo']?.toString() ??
      'Bloqueado: existen reservas o retenciones. No se permite editar ni eliminar.';
  Future<void> _conflicto(ExcepcionApi e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Los datos cambiaron'),
          content: Text(
            '${e.mensaje}\nSe descartará el formulario y se actualizarán los catálogos. Revisa los datos antes de volver a intentar.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Entendido y actualizar'),
            ),
          ],
        ),
      ),
    );
    await _cargar();
  }

  Future<void> _editar(String recurso, [Registro? registro]) async {
    if (_cargando || _mutando || _denegado) return;
    // Snapshot keeps the version frozen while the operator edits.
    final original = registro == null
        ? null
        : Map<String, dynamic>.from(registro);
    ExcepcionApi? conflicto;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FormularioOperacion(
        recurso: recurso,
        registro: original,
        catalogos: _catalogos,
        guardar: (datos) async {
          setState(() => _mutando = true);
          try {
            if (original == null) {
              await _api.post('/$recurso', body: datos);
            } else {
              await _api.put(
                '/$recurso/${Uri.encodeComponent(original['id'].toString())}',
                body: datos,
              );
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } on ExcepcionApi catch (e) {
            if (e.codigo == 409 || e.codigo == 404) {
              conflicto = e;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } else {
              if (e.codigo == 401 || e.codigo == 403) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _mostrarError(e);
              } else {
                rethrow;
              }
            }
          } finally {
            if (mounted) setState(() => _mutando = false);
          }
        },
      ),
    );
    if (!mounted) return;
    if (conflicto != null) {
      await _conflicto(conflicto!);
    } else if (!_denegado) {
      await _cargar();
    }
  }

  Future<bool> _confirmar(String titulo, String mensaje) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(titulo),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _eliminar(String recurso, Registro registro) async {
    final original = Map<String, dynamic>.from(registro);
    if (!await _confirmar(
      'Desactivar registro',
      '¿Desactivar ${titulo(recurso, original)}? El servidor conserva el historial y verifica sus referencias.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _mutando = true);
    try {
      await _api.delete(
        '/$recurso/${Uri.encodeComponent(original['id'].toString())}',
        body: {'version': original['version']},
      );
      await _cargar();
    } on ExcepcionApi catch (e) {
      if (e.codigo == 409 || e.codigo == 404) {
        await _conflicto(e);
      } else {
        _mostrarError(e);
      }
    } catch (e) {
      if (mounted) _mostrarError(e);
    } finally {
      if (mounted) setState(() => _mutando = false);
    }
  }

  Future<void> _promover(Usuario usuario) async {
    if (!await _confirmar(
      'Otorgar acceso ADMIN',
      '${usuario.nombre} podrá administrar catálogos, vuelos y usuarios. ¿Confirmas el cambio?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _mutando = true);
    try {
      await widget.apiService.promoverUsuario(usuario.id);
      await _cargar();
    } on ExcepcionApi catch (e) {
      if (e.codigo == 409) {
        await _conflicto(e);
      } else {
        _mostrarError(e);
      }
    } catch (e) {
      if (mounted) _mostrarError(e);
    } finally {
      if (mounted) setState(() => _mutando = false);
    }
  }

  String titulo(String recurso, Registro e) => switch (recurso) {
    'aeropuertos' => '${e['iata']} · ${e['nombre']}',
    'aviones' => '${e['matricula']} · ${e['modelo']}',
    'rutas' =>
      e['nombre']?.toString() ??
          '${e['origen']?['iata']} → ${e['destino']?['iata']}',
    _ => e['codigo']?.toString() ?? 'Vuelo',
  };
  String detalle(String recurso, Registro e) => switch (recurso) {
    'aeropuertos' =>
      '${e['ciudad']}, ${e['pais']}\n${e['zona_horaria']} · ${e['latitud']}, ${e['longitud']}',
    'aviones' =>
      '${e['capacidad_total']} asientos · ${(e['clases'] as List? ?? []).map((c) => '${c['nombre']}: ${c['capacidad'] ?? ''}').join(' · ')}',
    'rutas' => '${e['origen']?['ciudad']} → ${e['destino']?['ciudad']}',
    _ =>
      '${e['ruta']?['nombre'] ?? '${e['origen']} → ${e['destino']}'}\nSalida ${e['salida_local'] ?? e['salida_en']} · Llegada ${e['llegada_local'] ?? e['llegada_en']}\n${e['avion']?['matricula'] ?? ''} · ${e['asientos_disponibles']} asientos disponibles',
  };
  Widget _lista() {
    if (_indice == 4) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Administración de usuarios',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_usuarios.isEmpty) const Text('No hay usuarios disponibles.'),
          for (final u in _usuarios)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(u.correo),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(label: Text(u.rol)),
                        if (!u.esAdministrador)
                          OutlinedButton(
                            onPressed: _mutando || _cargando
                                ? null
                                : () => _promover(u),
                            child: const Text('Promover a ADMIN'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    final recurso = _recursos[_indice];
    final lista = (_catalogos[recurso] ?? [])
        .where((e) => e['activo'] != false)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titulos[_indice],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AerotechTheme.navy,
                  ),
                ),
                Text(
                  '${lista.length} registros activos',
                  style: const TextStyle(color: AerotechTheme.textSecondary),
                ),
              ],
            ),
            FilledButton.icon(
              key: ValueKey('crear_$recurso'),
              onPressed: _cargando || _mutando || _error != null
                  ? null
                  : () => _editar(recurso),
              icon: const Icon(Icons.add),
              label: const Text('Crear registro'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (lista.isEmpty && !_cargando)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(_iconos[_indice], size: 42, color: AerotechTheme.blue),
                  const SizedBox(height: 12),
                  const Text(
                    'Tu operación empieza aquí',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'Todavía no hay $recurso. Crea el primer registro para continuar.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        for (final e in lista)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo(recurso, e),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(detalle(recurso, e)),
                  if (bloqueado(e))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        motivo(e),
                        style: const TextStyle(color: AerotechTheme.blue),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: ValueKey('editar_${e['id']}'),
                        onPressed:
                            _cargando ||
                                _mutando ||
                                bloqueado(e) ||
                                _error != null
                            ? null
                            : () => _editar(recurso, e),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                      TextButton.icon(
                        key: ValueKey('eliminar_${e['id']}'),
                        onPressed:
                            _cargando ||
                                _mutando ||
                                bloqueado(e) ||
                                _error != null
                            ? null
                            : () => _eliminar(recurso, e),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Desactivar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.esAdministrador || _denegado) {
      return Scaffold(
        appBar: AppBar(title: const Text('AeroTech · Operaciones')),
        body: const Center(child: Text('Acceso exclusivo para ADMIN.')),
      );
    }
    return Scaffold(
      backgroundColor: AerotechTheme.background,
      appBar: AppBar(
        title: const Text('AeroTech · Operaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar catálogos',
            onPressed: _cargando || _mutando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_cargando || _mutando) const LinearProgressIndicator(),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _cargando ? null : _cargar,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          Expanded(
            child: AbsorbPointer(absorbing: _mutando, child: _lista()),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: _mutando
            ? null
            : (i) => setState(() => _indice = i),
        destinations: [
          for (var i = 0; i < _titulos.length; i++)
            NavigationDestination(icon: Icon(_iconos[i]), label: _titulos[i]),
        ],
      ),
    );
  }
}
