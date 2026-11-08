import 'package:flutter/material.dart';

import 'pages/login_page.dart';

void main() {
  runApp(const ReservasVuelosApp());
}

class ReservasVuelosApp extends StatelessWidget {
  const ReservasVuelosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AeroTech - Reservas de vuelos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: LoginPage(),
    );
  }
}
