import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/aerotech_theme.dart';
import '../validators/validaciones_autenticacion.dart';

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  bool _cargando = false;
  bool _mostrarContrasena = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_cargando) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await widget.apiService.registrarUsuario(
        nombre: ValidacionesAutenticacion.recortarComoApi(_nombre.text),
        correo: ValidacionesAutenticacion.recortarComoApi(_correo.text),
        contrasena: _contrasena.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cuenta creada. Ya puedes iniciar sesión.'),
        ),
      );
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ColoresRegistro.fondo,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Crear cuenta'),
        backgroundColor: _ColoresRegistro.fondo,
        foregroundColor: _ColoresRegistro.azulNoche,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final esEscritorio = constraints.maxWidth >= 700;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: esEscritorio ? 32 : 20,
                vertical: esEscritorio ? 36 : 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (esEscritorio ? 72 : 48),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _encabezado(),
                        const SizedBox(height: 26),
                        _formulario(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE5F1F8),
            border: Border.all(color: const Color(0xFFD1E2ED)),
          ),
          child: const Icon(
            Icons.flight_takeoff_rounded,
            color: _ColoresRegistro.azul,
            size: 27,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'AeroTech',
          style: TextStyle(
            color: _ColoresRegistro.azulNoche,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Viaja a tu manera',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ColoresRegistro.texto,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _formulario() {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: _ColoresRegistro.borde),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.always,
          onChanged: () => _formKey.currentState?.validate(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: _ColoresRegistro.cian,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                'Crear cuenta',
                style: TextStyle(
                  color: _ColoresRegistro.texto,
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Regístrate para comenzar tu próximo viaje.',
                style: TextStyle(
                  color: _ColoresRegistro.textoSuave,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _nombre,
                onChanged: _limpiarError,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: _decoracionCampo(
                  etiqueta: 'Nombre',
                  icono: Icons.person_outline_rounded,
                ),
                validator: ValidacionesAutenticacion.nombre,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _correo,
                onChanged: _limpiarError,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
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
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _registrar(),
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
                        color: _ColoresRegistro.textoSuave,
                      ),
                    ),
                validator: ValidacionesAutenticacion.contrasenaRegistro,
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
                  onPressed: _cargando ? null : _registrar,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ColoresRegistro.azul,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _ColoresRegistro.azul.withValues(
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
                      : const Text('Registrarme'),
                ),
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
      labelStyle: const TextStyle(color: _ColoresRegistro.textoSuave),
      prefixIconColor: _ColoresRegistro.textoSuave,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _ColoresRegistro.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _ColoresRegistro.azul, width: 1.7),
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

abstract final class _ColoresRegistro {
  static const fondo = AerotechTheme.background;
  static const azulNoche = AerotechTheme.navy;
  static const azul = AerotechTheme.blue;
  static const cian = AerotechTheme.cyan;
  static const texto = AerotechTheme.textPrimary;
  static const textoSuave = AerotechTheme.textSecondary;
  static const borde = AerotechTheme.border;
}
