import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../validators/validaciones_autenticacion.dart';
import '../presentacion/dialogo_aerotech.dart';

Future<bool> autenticarCompra(
  BuildContext context,
  ApiService api, {
  bool registroInicial = false,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AutenticacionCompra(api: api, registroInicial: registroInicial),
    ) ??
    false;

/// Autentica sin reemplazar la ruta ni descartar la selección de cabina.
class AutenticacionCompra extends StatefulWidget {
  const AutenticacionCompra({
    super.key,
    required this.api,
    this.registroInicial = false,
  });
  final ApiService api;
  final bool registroInicial;
  @override
  State<AutenticacionCompra> createState() => _AutenticacionCompraState();
}

class _AutenticacionCompraState extends State<AutenticacionCompra> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  late bool _registro;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registro = widget.registroInicial;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final correo = ValidacionesAutenticacion.recortarComoApi(_correo.text);
      if (_registro) {
        await widget.api.registrarUsuario(
          nombre: _nombre.text.trim(),
          correo: correo,
          contrasena: _clave.text,
        );
        // Si el ingreso posterior falla, un reintento no duplica el registro.
        if (mounted) setState(() => _registro = false);
      }
      await widget.api.iniciarSesion(correo: correo, contrasena: _clave.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DialogoAerotech(
    title: 'Identifícate para continuar',
    subtitle: 'Tu vuelo y tus asientos siguen seleccionados. Aún no se ha creado un pedido ni realizado ningún cargo.',
    eyebrow: 'CONTINÚA TU VIAJE',
    icon: Icons.person_outline,
    maxWidth: 520,
    onClose: () {
      if (!_busy) Navigator.pop(context, false);
    },
    actions: [
      FilledButton(
        onPressed: _busy ? null : _continuar,
        child: Text(
          _registro ? 'Crear cuenta y continuar' : 'Iniciar sesión y continuar',
        ),
      ),
    ],
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _registro = false;
                          _error = null;
                        }),
                  child: const Text('Ya tengo cuenta'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _registro = true;
                          _error = null;
                        }),
                  child: const Text('Crear cuenta'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_registro) ...[
            TextFormField(
              key: const ValueKey('compra-nombre'),
              controller: _nombre,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: ValidacionesAutenticacion.nombre,
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            key: const ValueKey('compra-correo'),
            controller: _correo,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: ValidacionesAutenticacion.correo,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('compra-contrasena'),
            controller: _clave,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _registro
                ? ValidacionesAutenticacion.contrasenaRegistro
                : ValidacionesAutenticacion.contrasenaLogin,
            onFieldSubmitted: (_) => _continuar(),
          ),
          if (_error != null) PanelMensaje(_error!, error: true),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
