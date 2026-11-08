import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'registro_page.dart';
import 'vuelos_page.dart';

class LoginPage extends StatefulWidget {
  LoginPage({super.key, ApiService? apiService})
    : apiService = apiService ?? ApiService();

  final ApiService apiService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await widget.apiService.iniciarSesion(
        correo: _correo.text.trim(),
        contrasena: _contrasena.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VuelosPage(apiService: widget.apiService),
        ),
      );
    } on ExcepcionApi catch (error) {
      _mostrarMensaje(error.mensaje);
    } catch (_) {
      _mostrarMensaje('No se pudo conectar con el servicio. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AeroTech'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.flight_takeoff, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    'Reserva tu próximo vuelo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _correo,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (valor) => valor == null || valor.trim().isEmpty
                        ? 'Ingresa tu correo'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contrasena,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    obscureText: true,
                    validator: (valor) => valor == null || valor.isEmpty
                        ? 'Ingresa tu contraseña'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _cargando ? null : _iniciarSesion,
                    child: _cargando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                  TextButton(
                    onPressed: _cargando
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  RegistroPage(apiService: widget.apiService),
                            ),
                          ),
                    child: const Text('Crear cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
