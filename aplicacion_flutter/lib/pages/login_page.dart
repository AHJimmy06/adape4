import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';
import '../validators/validaciones_autenticacion.dart';
import '../widgets/globo_vuelos.dart';
import 'registro_page.dart';
import 'sistema_vuelos_page.dart';

class LoginPage extends StatefulWidget {
  LoginPage({super.key, ApiService? apiService, this.globoBuilder})
    : apiService = apiService ?? ApiService();

  final ApiService apiService;
  final WidgetBuilder? globoBuilder;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  bool _cargando = false;
  bool _mostrarContrasena = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (_cargando) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);
    try {
      await widget.apiService.iniciarSesion(
        correo: ValidacionesAutenticacion.recortarComoApi(_correo.text),
        contrasena: _contrasena.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SistemaVuelosPage(apiService: widget.apiService),
        ),
      );
    } on ExcepcionApi catch (error) {
      _mostrarError(error.mensaje);
    } catch (_) {
      _mostrarError('No se pudo conectar con el servicio. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (mounted) setState(() => _error = mensaje);
  }

  void _limpiarError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  void _abrirRegistro() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegistroPage(apiService: widget.apiService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ColoresLogin.fondo,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return _vistaEscritorio(constraints.maxHeight);
          }
          return _vistaMovil();
        },
      ),
    );
  }

  Widget _vistaEscritorio(double alto) {
    return Row(
      children: [
        Expanded(
          flex: 11,
          child: _panelExperiencia(escritorio: true, alto: alto),
        ),
        Expanded(
          flex: 10,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _encabezadoFormulario(),
                    const SizedBox(height: 24),
                    _formulario(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _vistaMovil() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _panelExperiencia(escritorio: false, alto: 290),
                const SizedBox(height: 24),
                _encabezadoFormulario(),
                const SizedBox(height: 20),
                _formulario(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelExperiencia({required bool escritorio, required double alto}) {
    return Container(
      height: escritorio ? alto - 36 : alto,
      margin: escritorio ? const EdgeInsets.all(18) : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(
        horizontal: escritorio ? 12 : 20,
        vertical: escritorio ? 28 : 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07162F), Color(0xFF0D3653), Color(0xFF135D73)],
        ),
        borderRadius: BorderRadius.circular(escritorio ? 30 : 26),
        border: Border.all(color: const Color(0xFFDCEAF0)),
        boxShadow: [
          BoxShadow(
            color: _ColoresLogin.azulNoche.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Viaja a tu manera',
            style: TextStyle(
              color: Colors.white,
              fontSize: escritorio ? 25 : 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nuevos destinos te esperan',
            style: TextStyle(
              color: Colors.white70,
              fontSize: escritorio ? 14 : 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder:
                  widget.globoBuilder ??
                  (_) => const GloboVuelos(tamanoMaximo: 900, encuadre: 110),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoFormulario() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE5F1F8),
            border: Border.all(color: const Color(0xFFD1E2ED)),
          ),
          child: Icon(
            Icons.flight_takeoff_rounded,
            color: _ColoresLogin.azul,
            size: 25,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'AeroTech',
          style: TextStyle(
            color: _ColoresLogin.azulNoche,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tu próximo destino empieza aquí.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ColoresLogin.texto,
            fontSize: 21,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Encuentra vuelos y organiza tus reservas con facilidad.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ColoresLogin.textoSuave,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _formulario() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _ColoresLogin.borde),
        boxShadow: [
          BoxShadow(
            color: _ColoresLogin.azulNoche.withValues(alpha: 0.07),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.always,
        onChanged: () => _formKey.currentState?.validate(),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: _ColoresLogin.cian,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Text(
                'Reserva tu próximo vuelo',
                style: TextStyle(
                  color: _ColoresLogin.texto,
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inicia sesión para continuar con tu viaje.',
                style: TextStyle(
                  color: _ColoresLogin.textoSuave,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              TextFormField(
                controller: _correo,
                onChanged: _limpiarError,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: _decoracionCampo(
                  etiqueta: 'Correo',
                  icono: Icons.mail_outline_rounded,
                ),
                validator: ValidacionesAutenticacion.correo,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contrasena,
                onChanged: _limpiarError,
                obscureText: !_mostrarContrasena,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _iniciarSesion(),
                decoration:
                    _decoracionCampo(
                      etiqueta: 'Contraseña',
                      icono: Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: _mostrarContrasena
                            ? 'Ocultar contraseña'
                            : 'Mostrar contraseña',
                        onPressed: () => setState(
                          () => _mostrarContrasena = !_mostrarContrasena,
                        ),
                        icon: Icon(
                          _mostrarContrasena
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        color: _ColoresLogin.textoSuave,
                      ),
                    ),
                validator: ValidacionesAutenticacion.contrasenaLogin,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _cargando ? null : _iniciarSesion,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ColoresLogin.azul,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _ColoresLogin.azul.withValues(
                      alpha: 0.55,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _cargando
                      ? const SizedBox.square(
                          dimension: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Iniciar sesión'),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(
                    child: Text(
                      '¿Aún no tienes cuenta?',
                      style: TextStyle(color: _ColoresLogin.textoSuave),
                    ),
                  ),
                  TextButton(
                    onPressed: _abrirRegistro,
                    style: TextButton.styleFrom(
                      foregroundColor: _ColoresLogin.azul,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Crear cuenta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoracionCampo({
    required String etiqueta,
    required IconData icono,
  }) {
    return InputDecoration(
      labelText: etiqueta,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      fillColor: AerotechTheme.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: const TextStyle(color: _ColoresLogin.textoSuave),
      prefixIconColor: _ColoresLogin.textoSuave,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _ColoresLogin.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _ColoresLogin.azul, width: 1.7),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFCB4545)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFCB4545), width: 1.7),
      ),
    );
  }
}

abstract final class _ColoresLogin {
  static const fondo = AerotechTheme.background;
  static const azulNoche = AerotechTheme.navy;
  static const azul = AerotechTheme.blue;
  static const cian = AerotechTheme.cyan;
  static const texto = AerotechTheme.textPrimary;
  static const textoSuave = AerotechTheme.textSecondary;
  static const borde = AerotechTheme.border;
}
