import 'package:flutter/material.dart';

import '../../../models/usuario.dart';
import '../../../services/api_service.dart';
import '../../../theme/aerotech_theme.dart';

/// Administrative account creation never signs in as the new account.
class FormularioUsuario extends StatefulWidget {
  const FormularioUsuario({super.key, required this.guardar});
  final Future<void> Function(Map<String, dynamic>) guardar;

  @override
  State<FormularioUsuario> createState() => _FormularioUsuarioState();
}

class _FormularioUsuarioState extends State<FormularioUsuario> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  String _rol = 'USER';
  String? _error;
  bool _guardando = false, _visible = false, _aceptaAdmin = false;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    if (_rol == 'ADMIN' && !_aceptaAdmin) {
      setState(
        () => _error = 'Confirma que deseas otorgar acceso administrativo.',
      );
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.guardar({
        'nombre': _nombre.text.trim(),
        'correo': _correo.text.trim(),
        'contrasena': _contrasena.text,
        'rol': _rol,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ExcepcionApi
              ? e.mensaje
              : 'No se pudo crear el usuario. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_guardando,
    child: AlertDialog(
      scrollable: true,
      icon: const Icon(
        Icons.person_add_alt_1,
        color: AerotechTheme.blue,
        size: 32,
      ),
      title: const Text('Crear usuario'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Crea una cuenta sin cerrar tu sesión. Comparte sus credenciales por un canal seguro.',
              ),
              const SizedBox(height: 22),
              TextFormField(
                key: const ValueKey('usuario_nombre'),
                controller: _nombre,
                enabled: !_guardando,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty || v.trim().length > 120
                    ? 'Ingresa un nombre de hasta 120 caracteres.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('usuario_correo'),
                controller: _correo,
                enabled: !_guardando,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) =>
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v?.trim() ?? '')
                    ? 'Ingresa un correo válido.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('usuario_contrasena'),
                controller: _contrasena,
                enabled: !_guardando,
                obscureText: !_visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Entre 10 y 256 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _visible
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    onPressed: _guardando
                        ? null
                        : () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.length < 10 || v.length > 256
                    ? 'Usa entre 10 y 256 caracteres.'
                    : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: const ValueKey('usuario_rol'),
                initialValue: _rol,
                decoration: const InputDecoration(
                  labelText: 'Rol de acceso',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'USER',
                    child: Text('USER · Cliente'),
                  ),
                  DropdownMenuItem(
                    value: 'ADMIN',
                    child: Text('ADMIN · Administrador'),
                  ),
                ],
                onChanged: _guardando
                    ? null
                    : (v) => setState(() {
                        _rol = v!;
                        _aceptaAdmin = false;
                        _error = null;
                      }),
              ),
              if (_rol == 'ADMIN') ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _aceptaAdmin,
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _aceptaAdmin = v!),
                  title: const Text('Otorgar permisos de administrador'),
                  subtitle: const Text(
                    'Podrá administrar usuarios, catálogos y vuelos.',
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1),
          label: Text(_guardando ? 'Creando…' : 'Crear cuenta'),
        ),
      ],
    ),
  );
}

class ConfirmarRolUsuario extends StatefulWidget {
  const ConfirmarRolUsuario({
    super.key,
    required this.usuario,
    required this.guardar,
  });
  final Usuario usuario;
  final Future<void> Function() guardar;
  @override
  State<ConfirmarRolUsuario> createState() => _ConfirmarRolUsuarioState();
}

class _ConfirmarRolUsuarioState extends State<ConfirmarRolUsuario> {
  final _correo = TextEditingController();
  bool _guardando = false;
  String? _error;
  @override
  void dispose() {
    _correo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || _correo.text.trim() != widget.usuario.correo) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.guardar();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ExcepcionApi
              ? e.mensaje
              : 'No se pudo cambiar el rol. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final retirar = widget.usuario.esAdministrador;
    return PopScope(
      canPop: !_guardando,
      child: AlertDialog(
        scrollable: true,
        icon: Icon(
          retirar
              ? Icons.no_accounts_outlined
              : Icons.admin_panel_settings_outlined,
          color: AerotechTheme.blue,
          size: 32,
        ),
        title: Text(retirar ? 'Retirar acceso ADMIN' : 'Otorgar acceso ADMIN'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.usuario.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                retirar
                    ? 'Conservará su cuenta y sus reservas como USER, pero ya no podrá administrar el sistema.'
                    : 'Podrá administrar usuarios, catálogos y vuelos. Otorga este acceso solo a personas autorizadas.',
              ),
              const SizedBox(height: 20),
              SelectableText(
                'Escribe ${widget.usuario.correo} para confirmar.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('confirmar_correo'),
                controller: _correo,
                enabled: !_guardando,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Correo de confirmación',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed:
                _guardando || _correo.text.trim() != widget.usuario.correo
                ? null
                : _guardar,
            child: Text(_guardando ? 'Guardando…' : 'Confirmar cambio'),
          ),
        ],
      ),
    );
  }
}
