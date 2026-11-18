import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
      locale: const Locale('es', 'EC'),
      supportedLocales: const [Locale('es', 'EC')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AerotechTheme.light,
      home: LandingPage(globoBuilder: globoBuilder),
    );
  }
}
