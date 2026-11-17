import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'validacion_operaciones.dart';
import '../../services/api_service.dart';

typedef Registro = Map<String, dynamic>;

class FormularioOperacion extends StatefulWidget {
  const FormularioOperacion({
    super.key,
    required this.recurso,
    required this.catalogos,
    required this.guardar,
    this.registro,
  });
  final String recurso;
  final Map<String, List<Registro>> catalogos;
  final Registro? registro;
  final Future<void> Function(Registro) guardar;
  @override
  State<FormularioOperacion> createState() => _FormularioOperacionState();
}

class _FormularioOperacionState extends State<FormularioOperacion> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _campos = {};
  final List<_ClaseEditable> _clases = [];
  final Map<String, TextEditingController> _precios = {};
  String? _origen, _destino, _ruta, _avion, _error;
  DateTime? _salida, _llegada;
  bool _guardando = false;
  TextEditingController campo(String clave, [String inicial = '']) =>
      _campos.putIfAbsent(
        clave,
        () => TextEditingController(
          text: widget.registro?[clave]?.toString() ?? inicial,
        ),
      );
  List<Registro> catalogo(String nombre) => (widget.catalogos[nombre] ?? [])
      .where((e) => e['activo'] != false)
      .toList();
  Registro? buscar(String tipo, String? id) {
    for (final e in widget.catalogos[tipo] ?? <Registro>[]) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  Registro? get ruta => buscar('rutas', _ruta);
  Registro? get avion => buscar('aviones', _avion);
  List<Registro> get clasesAvion => (avion?['clases'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    _origen = r?['origen_id'];
    _destino = r?['destino_id'];
    _ruta = r?['ruta_id'] ?? r?['ruta']?['id'];
    _avion = r?['avion_id'] ?? r?['avion']?['id'];
    _salida = DateTime.tryParse(r?['salida_local']?.toString() ?? '');
    _llegada = DateTime.tryParse(r?['llegada_local']?.toString() ?? '');
    for (final c in r?['clases'] as List? ?? []) {
      _clases.add(_ClaseEditable(Map<String, dynamic>.from(c)));
    }
    if (_clases.isEmpty) _clases.add(_ClaseEditable(null));
    for (final t in r?['tarifas'] as List? ?? []) {
      final precio = t['precio_centavos'] as int;
      _precios[t['clase_codigo']] = TextEditingController(
        text: '${precio ~/ 100}.${(precio % 100).toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in [..._campos.values, ..._precios.values]) {
      c.dispose();
    }
    for (final c in _clases) {
      c.dispose();
    }
    super.dispose();
  }

  final _mayusculas = TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        newValue.copyWith(text: newValue.text.toUpperCase()),
  );
  Widget texto(
    String clave,
    String etiqueta, {
    String inicial = '',
    String? ayuda,
    String? Function(String?)? validar,
    bool mayusculas = false,
    int? maximo,
    TextInputType? teclado,
    List<TextInputFormatter>? formatos,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey(clave),
        controller: campo(clave, inicial),
        enabled: !_guardando,
        decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
        keyboardType: teclado,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: validar ?? ValidacionOperaciones.requerido,
        inputFormatters: [
          ...?formatos,
          if (mayusculas) _mayusculas,
          if (maximo != null) LengthLimitingTextInputFormatter(maximo),
        ],
      ),
    );
  }

  Widget selector(
    String clave,
    String etiqueta,
    List<Registro> elementos,
    String? actual,
    ValueChanged<String?> cambiar,
    String Function(Registro) nombre,
  ) {
    final valido = elementos.any((e) => e['id'] == actual) ? actual : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$clave-${valido ?? ''}'),
        initialValue: valido,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta),
        items: elementos
            .map(
              (e) => DropdownMenuItem<String>(
                value: e['id'].toString(),
                child: Text(nombre(e), overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _guardando ? null : cambiar,
        validator: (v) => v == null ? 'Selecciona una opción activa' : null,
      ),
    );
  }

  List<Widget> aeropuerto() => [
    texto(
      'iata',
      'Código IATA',
      mayusculas: true,
      maximo: 3,
      validar: (v) => RegExp(r'^[A-Z]{3}$').hasMatch(v ?? '')
          ? null
          : 'Usa exactamente 3 letras',
    ),
    texto('nombre', 'Nombre del aeropuerto'),
    texto('ciudad', 'Ciudad'),
    texto('pais', 'País'),
    texto(
      'codigo_pais',
      'Código ISO del país',
      mayusculas: true,
      maximo: 2,
      validar: (v) => RegExp(r'^[A-Z]{2}$').hasMatch(v ?? '')
          ? null
          : 'Usa exactamente 2 letras',
    ),
    texto(
      'latitud',
      'Latitud',
      teclado: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      validar: (v) => ValidacionOperaciones.coordenada(v, 90),
    ),
    texto(
      'longitud',
      'Longitud',
      teclado: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      validar: (v) => ValidacionOperaciones.coordenada(v, 180),
    ),
    texto(
      'zona_horaria',
      'Zona horaria IANA',
      inicial: 'America/Guayaquil',
      ayuda: 'Ejemplo: America/Guayaquil. El servidor valida la zona.',
      validar: (v) =>
          RegExp(r'^[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+$').hasMatch(v ?? '')
          ? null
          : 'Usa una zona IANA como America/Guayaquil',
    ),
  ];
  Widget campoClase(
    _ClaseEditable clase,
    String clave,
    String etiqueta, {
    bool numero = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: clase.campos[clave],
      decoration: InputDecoration(labelText: etiqueta),
      enabled: !_guardando,
      keyboardType: numero ? TextInputType.number : TextInputType.text,
      inputFormatters: numero
          ? [FilteringTextInputFormatter.digitsOnly]
          : clave == 'nombre'
          ? null
          : [_mayusculas],
      onChanged: (_) => setState(() {}),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) => numero
          ? (int.tryParse(v ?? '') ?? 0) < 1
                ? 'Debe ser mayor que cero'
                : null
          : ValidacionOperaciones.requerido(v),
    ),
  );
  List<Widget> aeronave() => [
    texto('matricula', 'Matrícula', mayusculas: true),
    texto('modelo', 'Modelo'),
    const Text(
      'Distribución de cabina',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
    const Text(
      'Las filas no se repiten entre clases. ABC|DEF representa dos grupos separados por un pasillo.',
    ),
    for (var i = 0; i < _clases.length; i++)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Clase ${i + 1}')),
                  IconButton(
                    tooltip: 'Quitar clase',
                    onPressed: _guardando || _clases.length == 1
                        ? null
                        : () => setState(() {
                            final c = _clases.removeAt(i);
                            c.dispose();
                          }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              campoClase(_clases[i], 'codigo', 'Código de clase'),
              campoClase(_clases[i], 'nombre', 'Nombre de clase'),
              campoClase(
                _clases[i],
                'fila_inicio',
                'Primera fila',
                numero: true,
              ),
              campoClase(_clases[i], 'filas', 'Número de filas', numero: true),
              campoClase(
                _clases[i],
                'columnas',
                'Grupos de columnas (ABC|DEF)',
              ),
              Text(
                'Capacidad de clase: ${ValidacionOperaciones.capacidad(_clases[i].datos)} asientos',
              ),
            ],
          ),
        ),
      ),
    Text(
      'Capacidad total: ${_clases.fold<int>(0, (s, c) => s + ValidacionOperaciones.capacidad(c.datos))} asientos',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    OutlinedButton.icon(
      onPressed: _guardando
          ? null
          : () => setState(() => _clases.add(_ClaseEditable(null))),
      icon: const Icon(Icons.add),
      label: const Text('Agregar clase'),
    ),
  ];
  List<Widget> itinerario() => [
    selector(
      'origen',
      'Aeropuerto de origen',
      catalogo('aeropuertos'),
      _origen,
      (v) => setState(() => _origen = v),
      (e) => '${e['iata']} · ${e['ciudad']}',
    ),
    selector(
      'destino',
      'Aeropuerto de destino',
      catalogo('aeropuertos'),
      _destino,
      (v) => setState(() => _destino = v),
      (e) => '${e['iata']} · ${e['ciudad']}',
    ),
    if (catalogo('aeropuertos').length < 2)
      const Text('Crea al menos dos aeropuertos activos antes de crear rutas.'),
  ];
  String zona(String extremo) =>
      ruta?[extremo]?['zona_horaria']?.toString() ?? 'Zona del aeropuerto';
  String fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  Future<void> elegirFecha(bool salida) async {
    final ahora = DateTime.now();
    final manana = DateTime(ahora.year, ahora.month, ahora.day + 1);
    final minimo = salida
        ? manana
        : _salida == null
        ? manana
        : DateTime(_salida!.year, _salida!.month, _salida!.day);
    final actual = (salida ? _salida : _llegada) ?? minimo;
    final dia = await showDatePicker(
      context: context,
      firstDate: minimo,
      lastDate: DateTime(ahora.year + 10, 12, 31),
      initialDate: actual.isBefore(minimo) ? minimo : actual,
      helpText: salida ? 'Fecha de salida' : 'Fecha de llegada',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (dia == null || !mounted) return;
    final tiempo = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual),
      helpText: salida ? 'Hora de salida local' : 'Hora de llegada local',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (tiempo == null || !mounted) return;
    setState(() {
      final valor = DateTime(
        dia.year,
        dia.month,
        dia.day,
        tiempo.hour,
        tiempo.minute,
      );
      if (salida) {
        _salida = valor;
        if (_llegada != null && fecha(_llegada!).compareTo(fecha(valor)) < 0) {
          _llegada = null;
        }
      } else {
        _llegada = valor;
      }
    });
  }

  List<Widget> vuelo() => [
    texto('codigo', 'Código del vuelo', mayusculas: true),
    selector(
      'ruta',
      'Ruta',
      catalogo('rutas'),
      _ruta,
      (v) => setState(() => _ruta = v),
      (e) =>
          e['nombre']?.toString() ??
          '${e['origen']?['iata']} → ${e['destino']?['iata']}',
    ),
    selector(
      'avion',
      'Avión',
      catalogo('aviones'),
      _avion,
      (v) => setState(() => _avion = v),
      (e) => '${e['matricula']} · ${e['modelo']}',
    ),
    const Text(
      'Horarios civiles locales de cada aeropuerto. La duración y los cruces de zona se validan en el servidor.',
    ),
    for (final esSalida in [true, false])
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton.icon(
          key: ValueKey(esSalida ? 'salida_local' : 'llegada_local'),
          onPressed: _guardando ? null : () => elegirFecha(esSalida),
          icon: const Icon(Icons.calendar_month),
          label: Text(
            '${esSalida ? 'Salida' : 'Llegada'} · ${zona(esSalida ? 'origen' : 'destino')}\n${(esSalida ? _salida : _llegada) == null ? 'Elegir fecha y hora' : '${fecha((esSalida ? _salida : _llegada)!)} ${hora((esSalida ? _salida : _llegada)!)}'}',
          ),
        ),
      ),
    if (avion != null)
      Text(
        'Capacidad de cabina: ${clasesAvion.fold<int>(0, (s, c) => s + ValidacionOperaciones.capacidad(c))} asientos (solo lectura)',
      ),
    for (final clase in clasesAvion)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          key: ValueKey('tarifa_${clase['codigo']}'),
          controller: _precios.putIfAbsent(
            clase['codigo'],
            () => TextEditingController(),
          ),
          decoration: InputDecoration(
            labelText: 'Tarifa base USD · ${clase['nombre']}',
            helperText: 'Mínimo USD 0.50. IVA 15% separado.',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !_guardando,
          inputFormatters: [
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  RegExp(r'^\d{0,7}(\.\d{0,2})?$').hasMatch(newValue.text)
                  ? newValue
                  : oldValue,
            ),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) => ValidacionOperaciones.centavos(v ?? '') == null
              ? 'Usa USD 0.50 o más, máximo dos decimales'
              : null,
        ),
      ),
    if (catalogo('rutas').isEmpty || catalogo('aviones').isEmpty)
      const Text('Primero crea una ruta activa y un avión con cabina.'),
  ];
  Future<void> guardar() async {
    if (!_form.currentState!.validate()) return;
    Registro datos;
    switch (widget.recurso) {
      case 'aeropuertos':
        datos = {
          for (final k in [
            'iata',
            'nombre',
            'ciudad',
            'pais',
            'codigo_pais',
            'zona_horaria',
          ])
            k: campo(k).text.trim(),
          'latitud': double.parse(campo('latitud').text),
          'longitud': double.parse(campo('longitud').text),
        };
      case 'aviones':
        final clases = _clases.map((c) => c.datos).toList();
        final error = ValidacionOperaciones.errorCabina(clases);
        if (error != null) {
          setState(() => _error = error);
          return;
        }
        datos = {
          'matricula': campo('matricula').text.trim(),
          'modelo': campo('modelo').text.trim(),
          'clases': clases,
        };
      case 'rutas':
        if (_origen == _destino) {
          setState(
            () => _error = 'El origen y el destino deben ser diferentes.',
          );
          return;
        }
        datos = {'origen_id': _origen, 'destino_id': _destino};
      default:
        final ahora = DateTime.now();
        final manana = DateTime(ahora.year, ahora.month, ahora.day + 1);
        if (_salida == null || _llegada == null || _salida!.isBefore(manana)) {
          setState(
            () => _error = 'Elige salida desde mañana y fecha/hora de llegada.',
          );
          return;
        }
        if (fecha(_llegada!).compareTo(fecha(_salida!)) < 0 ||
            (zona('origen') == zona('destino') &&
                !_llegada!.isAfter(_salida!))) {
          setState(() => _error = 'La llegada debe ser posterior a la salida.');
          return;
        }
        if (clasesAvion.isEmpty) {
          setState(() => _error = 'El avión debe tener una cabina válida.');
          return;
        }
        datos = {
          'codigo': campo('codigo').text.trim(),
          'ruta_id': _ruta,
          'avion_id': _avion,
          'salida_local': '${fecha(_salida!)}T${hora(_salida!)}',
          'llegada_local': '${fecha(_llegada!)}T${hora(_llegada!)}',
          'tarifas': [
            for (final c in clasesAvion)
              {
                'clase_codigo': c['codigo'],
                'precio_centavos': ValidacionOperaciones.centavos(
                  _precios[c['codigo']]!.text,
                ),
              },
          ],
        };
    }
    if (widget.registro != null) datos['version'] = widget.registro!['version'];
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.guardar(datos);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ExcepcionApi
              ? error.mensaje
              : 'No se pudo guardar. Revisa tu conexión y vuelve a intentar.',
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campos = switch (widget.recurso) {
      'aeropuertos' => aeropuerto(),
      'aviones' => aeronave(),
      'rutas' => itinerario(),
      _ => vuelo(),
    };
    return PopScope(
      canPop: !_guardando,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.registro == null ? 'Crear' : 'Editar'} · ${widget.recurso}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...campos,
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _guardando
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _guardando ? null : guardar,
                      child: Text(_guardando ? 'Guardando…' : 'Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClaseEditable {
  _ClaseEditable(Registro? datos)
    : campos = {
        for (final k in [
          'codigo',
          'nombre',
          'fila_inicio',
          'filas',
          'columnas',
        ])
          k: TextEditingController(
            text: k == 'columnas'
                ? (datos?['columnas'] as List? ??
                          [
                            ['A', 'B', 'C'],
                            ['D', 'E', 'F'],
                          ])
                      .map((g) => (g as List).join())
                      .join('|')
                : datos?[k]?.toString() ??
                      (k == 'fila_inicio' || k == 'filas'
                          ? '1'
                          : k == 'codigo'
                          ? 'ECO'
                          : 'Económica'),
          ),
      };
  final Map<String, TextEditingController> campos;
  Registro get datos => {
    'codigo': campos['codigo']!.text.trim(),
    'nombre': campos['nombre']!.text.trim(),
    'fila_inicio': int.tryParse(campos['fila_inicio']!.text) ?? 0,
    'filas': int.tryParse(campos['filas']!.text) ?? 0,
    'columnas': campos['columnas']!.text
        .trim()
        .split('|')
        .map((g) => g.split(''))
        .toList(),
  };
  void dispose() {
    for (final c in campos.values) {
      c.dispose();
    }
  }
}
