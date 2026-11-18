import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/sistema_api.dart';
import '../widgets/tarjeta_destino.dart';
import '../theme/aerotech_theme.dart';
import '../widgets/globo_vuelos.dart';
import 'login_page.dart';
import 'registro_page.dart';
import 'sistema_vuelos_page.dart';

class LandingPage extends StatefulWidget {
  LandingPage({super.key, ApiService? apiService, this.globoBuilder})
    : apiService = apiService ?? ApiService();

  final ApiService apiService;
  final WidgetBuilder? globoBuilder;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  bool _navegando = false, _cargandoVuelos = false;
  int _consultaVuelos = 0;
  String? _errorVuelos;
  List<Map<String, dynamic>> _vuelos = [];

  @override
  void initState() {
    super.initState();
    _cargarVuelos();
  }

  @override
  void didUpdateWidget(covariant LandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiService, widget.apiService)) _cargarVuelos();
  }

  Future<void> _cargarVuelos() async {
    final consulta = ++_consultaVuelos;
    setState(() {
      _cargandoVuelos = true;
      _errorVuelos = null;
    });
    try {
      final vuelos = await SistemaApi(widget.apiService)
          .lista('/vuelos', 'vuelos', requiereToken: false);
      if (mounted && consulta == _consultaVuelos) {
        setState(
          () => _vuelos = vuelos
              .where(
                (v) =>
                    v['activo'] != false &&
                    ((v['asientos_disponibles'] as num?) ?? 0) > 0,
              )
              .toList(),
        );
      }
    } catch (_) {
      if (mounted && consulta == _consultaVuelos) {
        setState(
          () => _errorVuelos =
              'No pudimos cargar los vuelos. Vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted && consulta == _consultaVuelos) {
        setState(() => _cargandoVuelos = false);
      }
    }
  }

  Future<void> _abrir({required bool registro}) async {
    if (_navegando) return;
    // Libera el visor mientras la siguiente pantalla está abierta.
    setState(() => _navegando = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => registro
            ? RegistroPage(apiService: widget.apiService)
            : LoginPage(
                apiService: widget.apiService,
                globoBuilder: widget.globoBuilder,
              ),
      ),
    );
    if (mounted) setState(() => _navegando = false);
  }

  Future<void> _explorar({Map<String, dynamic>? vueloInicial}) async {
    if (_navegando) return;
    setState(() => _navegando = true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SistemaVuelosPage(
          apiService: widget.apiService,
          vueloInicial: vueloInicial,
        ),
      ),
    );
    if (mounted) {
      setState(() => _navegando = false);
      _cargarVuelos();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AerotechTheme.background,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final amplio = constraints.maxWidth >= 1000;
          final margen = constraints.maxWidth >= 1600
              ? 48.0
              : amplio
              ? 32.0
              : 20.0;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(constraints, amplio, margen),
                Padding(
                  padding: EdgeInsets.fromLTRB(margen, 32, margen, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Tu viaje, de principio a fin',
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AerotechTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Un solo lugar para descubrir, reservar y organizar tu próximo destino.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AerotechTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        key: const ValueKey('landing-experiencia'),
                        width: double.infinity,
                        child: _experiencia(amplio),
                      ),
                      const SizedBox(height: 40),
                      _explorarVuelos(),
                      const SizedBox(height: 32),
                      const Divider(color: AerotechTheme.border),
                      const Padding(
                        padding: EdgeInsets.only(top: 18, bottom: 8),
                        child: Text(
                          'AeroTech · Tu próxima historia empieza con un vuelo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AerotechTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _hero(BoxConstraints constraints, bool amplio, double margen) {
    final escala = MediaQuery.textScalerOf(context).scale(1);
    final alto = math.max(
      constraints.maxHeight,
      860.0 + math.max(0.0, escala - 1) * 460,
    );
    final cabecera = <Widget>[
      _cabecera(),
      const SizedBox(height: 24),
      const Divider(color: Colors.white24),
      SizedBox(height: amplio ? 24 : 28),
    ];
    if (amplio) {
      return _fondoHero(
        SizedBox(
          key: const ValueKey('landing-hero'),
          height: alto,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: margen, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...cabecera,
                Expanded(
                  child: Center(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 32),
                              child: _presentacion(true),
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: _mundo(maximo: math.min(980, alto - 150)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _fondoHero(
      ConstrainedBox(
        key: const ValueKey('landing-hero'),
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: margen, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...cabecera,
              _presentacion(false),
              const SizedBox(height: 28),
              _mundo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fondoHero(Widget child) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff07162f), Color(0xff0d3653), Color(0xff135d73)],
      ),
    ),
    child: child,
  );

  Widget _explorarVuelos() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          const Text(
            'Explorar vuelos',
            style: TextStyle(
              fontSize: 28,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: AerotechTheme.navy,
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('landing-buscar-mas'),
            onPressed: _navegando ? null : () => _explorar(),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Buscar más'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Salidas disponibles, precios claros y un viaje que empieza a tu manera.',
        style: TextStyle(color: AerotechTheme.textSecondary),
      ),
      const SizedBox(height: 24),
      if (_cargandoVuelos)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 12),
              Text('Buscando tu próximo destino…'),
            ],
          ),
        )
      else if (_errorVuelos != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_errorVuelos!),
                const SizedBox(height: 12),
                TextButton.icon(
                  key: const ValueKey('landing-reintentar-vuelos'),
                  onPressed: _cargarVuelos,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a intentar'),
                ),
              ],
            ),
          ),
        )
      else if (_vuelos.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('Pronto habrá nuevos destinos para descubrir.'),
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final cantidad = math.max(
              1,
              ((constraints.maxWidth + 16) / 316).floor(),
            );
            final visibles = _vuelos.take(cantidad).toList();
            return IntrinsicHeight(
              child: Row(
                key: const ValueKey('landing-fila-vuelos'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < visibles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(
                      child: TarjetaDestino(
                        key: ValueKey('landing-vuelo-${visibles[i]['id']}'),
                        vuelo: visibles[i],
                        onReservar: _navegando
                            ? null
                            : () => _explorar(vueloInicial: visibles[i]),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
    ],
  );

  Widget _cabecera() => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AerotechTheme.navy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.flight_takeoff_rounded,
            color: AerotechTheme.cyan,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'AeroTech',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.8,
              color: Colors.white,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(280, constraints.maxWidth * .42),
          ),
          child: TextButton(
            onPressed: () => _abrir(registro: false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Iniciar sesión'),
          ),
        ),
      ],
    ),
  );

  Widget _presentacion(bool amplio) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: AerotechTheme.cyan.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Text(
          'UN MUNDO DE POSIBILIDADES',
          style: TextStyle(
            color: Color(0xff7ee6ed),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            fontSize: 11,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Semantics(
        header: true,
        child: Text(
          'El mundo está\nmás cerca.',
          style: TextStyle(
            color: Colors.white,
            fontSize: amplio ? 84 : 48,
            height: 1.06,
            letterSpacing: amplio ? -2 : -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(height: 20),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: const Text(
          'Hay lugares que todavía no conoces e historias que esperan por ti. '
          'Encuentra tu próximo vuelo y empieza a imaginar el viaje.',
          style: TextStyle(color: Colors.white70, fontSize: 18, height: 1.55),
        ),
      ),
      const SizedBox(height: 28),
      _acciones(),
      const SizedBox(height: 20),
      const Text(
        'Una nueva historia entre dos destinos',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Tus destinos. Tus planes. Tu manera de viajar.',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ],
  );

  Widget _acciones() => LayoutBuilder(
    builder: (context, constraints) {
      final ancho = constraints.maxWidth < 420
          ? constraints.maxWidth
          : ((constraints.maxWidth - 12) / 2).clamp(0.0, 196.0).toDouble();
      final forma = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      );
      final alto =
          52.0 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
            0,
            double.infinity,
          );
      final tamano = Size(ancho, alto);
      const texto = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            key: const ValueKey('landing-explorar-vuelos'),
            onPressed: _navegando ? null : () => _explorar(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Explorar vuelos'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff7ee6ed),
              foregroundColor: AerotechTheme.navy,
              fixedSize: tamano,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: forma,
              textStyle: texto,
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('landing-crear-cuenta'),
            onPressed: _navegando ? null : () => _abrir(registro: true),
            icon: const Icon(Icons.travel_explore_rounded, size: 20),
            label: const Text('Crear cuenta'),
            style: OutlinedButton.styleFrom(
              fixedSize: tamano,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: forma,
              textStyle: texto,
            ),
          ),
        ],
      );
    },
  );

  Widget _mundo({double maximo = 440}) {
    final estatico = _navegando || ModalRoute.isCurrentOf(context) == false;
    final movimientoReducido = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maximo),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AerotechTheme.cyan.withValues(alpha: 0.22),
                        AerotechTheme.cyan.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                if (estatico)
                  const Icon(
                    Icons.public_rounded,
                    key: ValueKey('landing-globo-estatico'),
                    size: 180,
                    color: AerotechTheme.blue,
                    semanticLabel: 'El mundo de AeroTech',
                  )
                else
                  widget.globoBuilder?.call(context) ??
                      GloboVuelos(
                        key: ValueKey('landing-globo-$movimientoReducido'),
                        animar: !movimientoReducido,
                        tamanoMaximo: maximo,
                        encuadre: 110,
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _experiencia(bool amplio) {
    const tarjetas = [
      _Ventaja(
        numero: '01',
        icono: Icons.travel_explore_rounded,
        titulo: 'Encuentra tu ruta',
        detalle:
            'Consulta los vuelos y descubre cómo llegar a tu próximo destino.',
      ),
      _Ventaja(
        numero: '02',
        icono: Icons.flight_takeoff_rounded,
        titulo: 'Imagina el recorrido',
        detalle: 'Explora la ruta y la vista de la cabina antes de reservar.',
      ),
      _Ventaja(
        numero: '03',
        icono: Icons.confirmation_number_outlined,
        titulo: 'Organiza tu viaje',
        detalle: 'Consulta tus reservas y accede a los detalles de cada vuelo.',
      ),
    ];
    if (!amplio) {
      return const Column(children: tarjetas);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i != 0) const SizedBox(width: 16),
            Expanded(child: tarjetas[i]),
          ],
        ],
      ),
    );
  }
}

class _Ventaja extends StatelessWidget {
  const _Ventaja({
    required this.numero,
    required this.icono,
    required this.titulo,
    required this.detalle,
  });
  final String numero;
  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 224),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AerotechTheme.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AerotechTheme.cyan.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: AerotechTheme.blue, size: 24),
            ),
            Text(
              numero,
              style: const TextStyle(
                color: AerotechTheme.textSecondary,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AerotechTheme.navy,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          detalle,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AerotechTheme.textSecondary,
          ),
        ),
      ],
    ),
  );
}
