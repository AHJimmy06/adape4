import 'package:flutter/material.dart';

import '../services/api_service.dart';

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

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await widget.apiService.registrarUsuario(
        nombre: _nombre.text.trim(),
        correo: _correo.text.trim(),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
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
                  TextFormField(
                    controller: _nombre,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (valor) => valor == null || valor.trim().isEmpty
                        ? 'Ingresa tu nombre'
                        : null,
                  ),
                  const SizedBox(height: 16),
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
                    validator: (valor) => valor == null || valor.length < 8
                        ? 'Usa al menos 8 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _cargando ? null : _registrar,
                    child: _cargando
                        ? const CircularProgressIndicator()
                        : const Text('Registrarme'),
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
