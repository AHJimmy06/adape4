// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

@JS('aerotechStripe.mount')
external void _mount(
  JSString id,
  JSString key,
  JSString secret,
  JSFunction complete,
  JSFunction error,
);
@JS('aerotechStripe.destroy')
external void _destroy(JSString id);

class StripeEmbebido extends StatefulWidget {
  const StripeEmbebido({
    super.key,
    required this.clientSecret,
    required this.publishableKey,
    required this.onComplete,
  });
  final String clientSecret, publishableKey;
  final VoidCallback onComplete;
  @override
  State<StripeEmbebido> createState() => _StripeEmbebidoState();
}

class _StripeEmbebidoState extends State<StripeEmbebido> {
  static var _nextId = 0;
  late final _id = 'aerotech-stripe-${_nextId++}';
  String? _error;
  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(
      _id,
      (_) => html.DivElement()
        ..id = _id
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'auto',
    );
  }

  void _created(int _) {
    try {
      _mount(
        _id.toJS,
        widget.publishableKey.toJS,
        widget.clientSecret.toJS,
        (() {
          if (mounted) widget.onComplete();
        }).toJS,
        ((JSString _) {
          if (mounted) {
            setState(
              () => _error = 'No se pudo cargar el formulario seguro. Cierra y vuelve a abrir el pedido.',
            );
          }
        }).toJS,
      );
    } catch (_) {
      setState(
        () => _error =
            'No se pudo iniciar Stripe. Recarga AeroTech e intenta nuevamente.',
      );
    }
  }

  @override
  void dispose() {
    try {
      _destroy(_id.toJS);
    } catch (_) {
      // El puente puede faltar si el navegador bloqueó su descarga inicial.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
      : SizedBox.expand(
          child: HtmlElementView(
            viewType: _id,
            onPlatformViewCreated: _created,
          ),
        );
}
