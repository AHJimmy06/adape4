import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
  bool _navegando = false;

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

  Future<void> _explorar() async {
    if (_navegando) return;
    setState(() => _navegando = true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SistemaVuelosPage(apiService: widget.apiService),
      ),
    );
    if (mounted) setState(() => _navegando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AerotechTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final amplio = constraints.maxWidth >= 900;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: amplio ? 48 : 20,
                      vertical: amplio ? 24 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _cabecera(),
                        const SizedBox(height: 24),
                        const Divider(color: AerotechTheme.border),
                        SizedBox(height: amplio ? 40 : 32),
                        if (amplio)
                          Row(
                            children: [
                              Expanded(child: _presentacion(amplio)),
                              const SizedBox(width: 48),
                              Expanded(child: _mundo()),
                            ],
                          )
                        else ...[
                          _presentacion(amplio),
                          const SizedBox(height: 28),
                          _mundo(),
                        ],
                        const SizedBox(height: 48),
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
                        _experiencia(amplio),
                        const SizedBox(height: 28),
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
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera() => Row(
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
            color: AerotechTheme.navy,
          ),
        ),
      ),
      TextButton(
        onPressed: () => _abrir(registro: false),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: const Text('Iniciar sesión'),
      ),
    ],
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
            color: AerotechTheme.blue,
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
            color: AerotechTheme.navy,
            fontSize: amplio ? 58 : 42,
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
          style: TextStyle(
            color: AerotechTheme.textSecondary,
            fontSize: 16,
            height: 1.55,
          ),
        ),
      ),
      const SizedBox(height: 28),
      _acciones(),
      const SizedBox(height: 20),
      const Text(
        'Tus destinos. Tus planes. Tu manera de viajar.',
        style: TextStyle(color: AerotechTheme.textSecondary, fontSize: 12),
      ),
    ],
  );

  Widget _acciones() => LayoutBuilder(
    builder: (context, constraints) {
      final ancho = constraints.maxWidth < 350
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
            key: const ValueKey('landing-crear-cuenta'),
            onPressed: () => _abrir(registro: true),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Crear cuenta'),
            style: FilledButton.styleFrom(
              fixedSize: tamano,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: forma,
              textStyle: texto,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _explorar,
            icon: const Icon(Icons.travel_explore_rounded, size: 20),
            label: const Text('Explorar vuelos'),
            style: OutlinedButton.styleFrom(
              fixedSize: tamano,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              foregroundColor: AerotechTheme.navy,
              side: const BorderSide(color: AerotechTheme.border),
              shape: forma,
              textStyle: texto,
            ),
          ),
        ],
      );
    },
  );

  Widget _mundo() {
    final estatico = _navegando || ModalRoute.isCurrentOf(context) == false;
    final movimientoReducido = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
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
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flight_rounded, size: 17, color: AerotechTheme.blue),
            SizedBox(width: 9),
            Flexible(
              child: Text(
                'Una nueva historia entre dos destinos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AerotechTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
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
