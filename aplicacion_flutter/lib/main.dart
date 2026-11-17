import 'package:flutter/material.dart';

import 'pages/landing_page.dart';
import 'theme/aerotech_theme.dart';

void main() {
  runApp(const ReservasVuelosApp());
}

class ReservasVuelosApp extends StatelessWidget {
  const ReservasVuelosApp({super.key, this.globoBuilder});

  final WidgetBuilder? globoBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AeroTech - Reservas de vuelos',
      debugShowCheckedModeBanner: false,
      theme: AerotechTheme.light,
      home: LandingPage(globoBuilder: globoBuilder),
    );
  }
}
