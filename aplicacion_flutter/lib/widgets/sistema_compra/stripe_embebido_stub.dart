import 'package:flutter/material.dart';

class StripeEmbebido extends StatelessWidget {
  const StripeEmbebido({
    super.key,
    required this.clientSecret,
    required this.publishableKey,
    required this.onComplete,
  });
  final String clientSecret, publishableKey;
  final VoidCallback onComplete;
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(20),
    child: Text(
      'El formulario seguro está disponible en AeroTech Web. '
      'Tu pedido sigue guardado en Pendientes de pago.',
    ),
  );
}
