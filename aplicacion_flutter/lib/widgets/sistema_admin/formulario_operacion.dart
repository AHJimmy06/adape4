import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'validacion_operaciones.dart';
import '../../services/api_service.dart';
import '../presentacion/dialogo_aerotech.dart';
import '../../theme/aerotech_theme.dart';
import '../../utils/checkout_operacion.dart';

typedef Registro = Map<String, dynamic>;

class FormularioOperacion extends StatefulWidget {
  const FormularioOperacion({
    super.key,
    required this.recurso,
    required this.catalogos,
    required this.guardar,
    this.registro,
    this.consultarDisponibilidad,
  });
  final String recurso;
  final Map<String, List<Registro>> catalogos;
  final Registro? registro;
  final Future<void> Function(Registro) guardar;
  final Future<Registro> Function(Registro parametros)? consultarDisponibilidad;
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
  DateTime? _fechaFin;
  String _frecuencia = 'unico';
  String? _programacionSolicitud, _programacionClave;
  bool _guardando = false;
  int _franja = 60, _consultaCapacidad = 0;
  Registro? _capacidad;
  String? _errorCapacidad;
  bool _consultandoCapacidad = false;
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
    final franja = r?['franja_minutos'];
    _franja = const [15, 30, 60, 120].contains(franja)
        ? (franja as num).toInt()
        : 60;
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
    if (widget.recurso == 'vuelos') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consultarCapacidad();
      });
    }
  }

  Future<void> _consultarCapacidad() async {
    final consulta = ++_consultaCapacidad;
    final destino = ruta?['destino']?['id'];
    final llegada = _llegada;
    if (widget.consultarDisponibilidad == null ||
        destino == null ||
        llegada == null) {
      if (mounted) {
        setState(() {
          _capacidad = null;
          _errorCapacidad = null;
          _consultandoCapacidad = false;
        });
      }
      return;
    }
    setState(() {
      _capacidad = null;
      _errorCapacidad = null;
      _consultandoCapacidad = true;
    });
    try {
      final datos = await widget.consultarDisponibilidad!({
        'aeropuerto_id': destino,
        'llegada_local': '${fecha(llegada)}T${hora(llegada)}',
        if (widget.registro?['id'] != null) 'vuelo_id': widget.registro!['id'],
      });
      if (mounted && consulta == _consultaCapacidad) {
        setState(() => _capacidad = datos);
      }
    } catch (_) {
      if (mounted && consulta == _consultaCapacidad) {
        setState(
          () => _errorCapacidad = 'No se pudo consultar la capacidad del aeropuerto. Se validará al guardar.',
        );
      }
    } finally {
      if (mounted && consulta == _consultaCapacidad) {
        setState(() => _consultandoCapacidad = false);
      }
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
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 4,
        ),
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
    const _SeccionFormulario('Capacidad de aterrizajes', Icons.flight_land),
    Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 250,
          child: texto(
            'capacidad_aterrizajes',
            'Aterrizajes por franja',
            inicial: '10',
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.digitsOnly],
            validar: (v) =>
                (int.tryParse(v ?? '') ?? 0) < 1 ||
                    (int.tryParse(v ?? '') ?? 0) > 1000
                ? 'Entre 1 y 1000 aterrizajes'
                : null,
          ),
        ),
        SizedBox(
          width: 250,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('franja_minutos'),
            isExpanded: true,
            initialValue: _franja,
            decoration: const InputDecoration(
              labelText: 'Duración de la franja',
            ),
            items: [
              for (final n in [15, 30, 60, 120])
                DropdownMenuItem(value: n, child: Text('$n minutos')),
            ],
            onChanged: _guardando
                ? null
                : (n) => setState(() => _franja = n ?? 60),
          ),
        ),
      ],
    ),
    const Text(
      'Límite de llegadas programadas dentro de cada franja local del aeropuerto.',
    ),
    const _SeccionFormulario('Ubicación y zona horaria', Icons.public),
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
    double ancho = 100,
  }) => SizedBox(
    width: ancho,
    child: Semantics(
      label: etiqueta,
      child: TextFormField(
        controller: clase.campos[clave],
        decoration: InputDecoration(
          hintText: numero ? '1' : null,
          isDense: true,
          errorMaxLines: 2,
        ),
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
                  ? 'Mayor que cero'
                  : null
            : ValidacionOperaciones.requerido(v),
      ),
    ),
  );

  Widget tabla(List<String> titulos, List<DataRow> filas) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          horizontalMargin: 12,
          columnSpacing: 16,
          dataRowMinHeight: 78,
          dataRowMaxHeight: 106,
          headingRowColor: WidgetStateProperty.all(AerotechTheme.inputFill),
          columns: [for (final t in titulos) DataColumn(label: Text(t))],
          rows: filas,
        ),
      );

  List<Widget> aeronave() => [
    texto('matricula', 'Matrícula', mayusculas: true),
    texto('modelo', 'Modelo'),
    const _SeccionFormulario(
      'Distribución de cabina',
      Icons.event_seat_outlined,
    ),
    const Text(
      'ABC|DEF representa grupos separados por un pasillo. Las filas no pueden repetirse entre clases.',
    ),
    tabla(
      ['Código', 'Clase', 'Primera fila', 'Filas', 'Columnas', 'Asientos', ''],
      [
        for (final clase in _clases)
          DataRow(
            key: ObjectKey(clase),
            cells: [
              DataCell(
                campoClase(clase, 'codigo', 'Código de clase', ancho: 85),
              ),
              DataCell(
                campoClase(clase, 'nombre', 'Nombre de clase', ancho: 140),
              ),
              DataCell(
                campoClase(
                  clase,
                  'fila_inicio',
                  'Primera fila',
                  numero: true,
                  ancho: 70,
                ),
              ),
              DataCell(
                campoClase(
                  clase,
                  'filas',
                  'Número de filas',
                  numero: true,
                  ancho: 70,
                ),
              ),
              DataCell(
                campoClase(clase, 'columnas', 'Grupos de columnas', ancho: 120),
              ),
              DataCell(Text('${ValidacionOperaciones.capacidad(clase.datos)}')),
              DataCell(
                IconButton(
                  tooltip: 'Quitar clase',
                  onPressed: _guardando || _clases.length == 1
                      ? null
                      : () => setState(() {
                          _clases.remove(clase);
                          clase.dispose();
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
      ],
    ),
    const SizedBox(height: 12),
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

  Widget _tarifa(Registro clase) => SizedBox(
    width: 180,
    child: TextFormField(
      key: ValueKey('tarifa_${clase['codigo']}'),
      controller: _precios.putIfAbsent(
        clase['codigo'],
        () => TextEditingController(),
      ),
      decoration: InputDecoration(
        hintText: 'USD 0.50',
        isDense: true,
        errorMaxLines: 2,
        semanticCounterText: 'Tarifa base USD ${clase['nombre']}',
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
          ? 'USD 0.50 o más, dos decimales'
          : null,
    ),
  );

  Widget _panelCapacidad() {
    if (_consultandoCapacidad) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    }
    if (_errorCapacidad != null) {
      return PanelMensaje(_errorCapacidad!, error: true);
    }
    if (_capacidad == null) {
      return const Text(
        'Elige la ruta y la llegada para consultar los cupos del aeropuerto.',
      );
    }
    final restantes = (_capacidad!['disponibles'] as num?)?.toInt() ?? 0;
    return PanelMensaje(
      '$restantes aterrizajes disponibles en esta franja de ${_capacidad!['franja_minutos']} minutos. '
      '${_capacidad!['programados']} programados / ${_capacidad!['capacidad_aterrizajes']} permitidos. '
      '${_capacidad!['inicio_local']} — ${_capacidad!['fin_local']}. '
      'La disponibilidad se vuelve a validar al guardar.',
      error: restantes <= 0,
    );
  }

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
        if (_fechaFin != null &&
            (_fechaFin!.isBefore(
                  DateTime(valor.year, valor.month, valor.day),
                ) ||
                _fechaFin!
                        .difference(
                          DateTime(valor.year, valor.month, valor.day),
                        )
                        .inDays >=
                    90)) {
          _fechaFin = null;
        }
        if (_llegada != null && fecha(_llegada!).compareTo(fecha(valor)) < 0) {
          _llegada = null;
        }
      } else {
        _llegada = valor;
      }
    });
    _consultarCapacidad();
  }

  Future<void> elegirFin() async {
    if (_salida == null) return;
    final inicio = DateTime(_salida!.year, _salida!.month, _salida!.day);
    final fin = await showDatePicker(
      context: context,
      initialDate: _fechaFin ?? inicio,
      firstDate: inicio,
      lastDate: DateTime(inicio.year, inicio.month, inicio.day + 89),
      helpText: 'Última salida de la programación diaria',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (fin != null && mounted) setState(() => _fechaFin = fin);
  }

  List<Widget> vuelo() => [
    InputDecorator(
      decoration: const InputDecoration(labelText: 'Código del vuelo'),
      child: Text(
        widget.registro?['codigo']?.toString() ??
            'Se asignará el siguiente número al guardar',
      ),
    ),
    const SizedBox(height: 14),
    if (widget.registro == null) ...[
      DropdownButtonFormField<String>(
        key: const ValueKey('frecuencia_vuelo'),
        initialValue: _frecuencia,
        decoration: const InputDecoration(labelText: 'Frecuencia del vuelo'),
        items: const [
          DropdownMenuItem(
            value: 'unico',
            child: Text('Único · una sola fecha'),
          ),
          DropdownMenuItem(
            value: 'diaria',
            child: Text('Diario · repetir entre fechas'),
          ),
        ],
        onChanged: _guardando
            ? null
            : (value) => setState(() => _frecuencia = value ?? 'unico'),
      ),
      const SizedBox(height: 14),
    ],
    selector(
      'ruta',
      'Ruta',
      catalogo('rutas'),
      _ruta,
      (v) {
        setState(() => _ruta = v);
        _consultarCapacidad();
      },
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
    const _SeccionFormulario('Horarios del viaje', Icons.schedule),
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
    if (widget.registro == null && _frecuencia == 'diaria') ...[
      OutlinedButton.icon(
        key: const ValueKey('fecha_fin_programacion'),
        onPressed: _guardando || _salida == null ? null : elegirFin,
        icon: const Icon(Icons.date_range),
        label: Text(
          _salida == null
              ? 'Selecciona primero la salida'
              : _fechaFin == null
              ? 'Elegir última fecha de salida'
              : 'Hasta ${fecha(_fechaFin!)}',
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _fechaFin == null || _salida == null
            ? 'Se creará un vuelo por día, hasta 90 días. Cada fecha tendrá su propia disponibilidad.'
            : '${_fechaFin!.difference(DateTime(_salida!.year, _salida!.month, _salida!.day)).inDays + 1} vuelos diarios · misma ruta, avión y horarios locales.',
      ),
      const SizedBox(height: 14),
    ],
    if (avion != null)
      const _SeccionFormulario('Cabina y tarifas', Icons.payments_outlined),
    if (avion != null)
      Text(
        'Capacidad de cabina: ${clasesAvion.fold<int>(0, (s, c) => s + ValidacionOperaciones.capacidad(c))} asientos (solo lectura)',
      ),
    if (clasesAvion.isNotEmpty) ...[
      const Text('Tarifas base en USD. IVA 15% se calcula por separado.'),
      tabla(
        ['Clase', 'Filas', 'Asientos', 'Tarifa base USD'],
        [
          for (final clase in clasesAvion)
            DataRow(
              cells: [
                DataCell(Text('${clase['nombre']} · ${clase['codigo']}')),
                DataCell(
                  Text(
                    '${clase['fila_inicio']} – ${(clase['fila_inicio'] as num).toInt() + (clase['filas'] as num).toInt() - 1}',
                  ),
                ),
                DataCell(Text('${ValidacionOperaciones.capacidad(clase)}')),
                DataCell(_tarifa(clase)),
              ],
            ),
        ],
      ),
    ],
    const _SeccionFormulario(
      'Capacidad del aeropuerto de llegada',
      Icons.flight_land,
    ),
    _panelCapacidad(),
    if (_frecuencia == 'diaria')
      const Text(
        'En vuelos diarios se validarán todas las fechas de la programación.',
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
          'capacidad_aterrizajes': int.parse(
            campo('capacidad_aterrizajes', '10').text,
          ),
          'franja_minutos': _franja,
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
          if (widget.registro != null) 'codigo': widget.registro!['codigo'],
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
        if (widget.registro == null && _frecuencia == 'diaria') {
          if (_fechaFin == null) {
            setState(
              () => _error = 'Elige la última fecha de la programación diaria.',
            );
            return;
          }
          datos['frecuencia'] = 'diaria';
          datos['fecha_fin'] = fecha(_fechaFin!);
          final solicitud = jsonEncode(datos);
          if (_programacionSolicitud != solicitud) {
            _programacionSolicitud = solicitud;
            _programacionClave = nuevaClaveOperacion();
          }
          datos['clave_operacion'] = _programacionClave;
        }
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
      child: DialogoAerotech(
        maxWidth: widget.recurso == 'aviones' || widget.recurso == 'vuelos'
            ? 900
            : 760,
        title:
            '${widget.registro == null ? 'Crear' : 'Editar'} · ${widget.recurso}',
        subtitle: 'Completa los datos de la operación. Revisa los campos antes de guardar.',
        eyebrow: 'CENTRO DE OPERACIONES',
        icon: switch (widget.recurso) {
          'aeropuertos' => Icons.local_airport,
          'aviones' => Icons.airplanemode_active,
          'rutas' => Icons.route_outlined,
          _ => Icons.flight_takeoff,
        },
        actions: [
          TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _guardando ? null : guardar,
            child: Text(_guardando ? 'Guardando…' : 'Guardar'),
          ),
        ],
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'DATOS DEL REGISTRO',
                style: TextStyle(
                  color: AerotechTheme.blue,
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              ...campos,
              if (_error != null) PanelMensaje(_error!, error: true),
            ],
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

class _SeccionFormulario extends StatelessWidget {
  const _SeccionFormulario(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 16),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AerotechTheme.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AerotechTheme.navy,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
        ),
      ],
    ),
  );
}
