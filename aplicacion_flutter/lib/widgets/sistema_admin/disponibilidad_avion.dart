import 'package:flutter/material.dart';

import '../presentacion/dialogo_aerotech.dart';

/// Horarios informativos; el servidor vuelve a validar al guardar el vuelo.
class DisponibilidadAvion extends StatelessWidget {
  const DisponibilidadAvion({
    super.key,
    required this.datos,
    required this.cargando,
    required this.onActualizar,
    required this.onSeleccionar,
    this.error,
    this.bloqueado = false,
  });
  final Map<String, dynamic>? datos;
  final bool cargando, bloqueado;
  final String? error;
  final VoidCallback onActualizar;
  final void Function(DateTime salida, DateTime llegada) onSeleccionar;

  static String horario(Object? valor) => (valor?.toString() ?? '')
      .replaceFirst('T', ' ')
      .substring(0, (valor?.toString().length ?? 0).clamp(0, 16));

  List<Map<String, dynamic>> lista(String clave) =>
      (datos?[clave] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  // Los horarios civiles no pertenecen a la zona del dispositivo.
  static DateTime civil(String valor) {
    final d = DateTime.parse(valor);
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
  }

  static DateTime sumarCivil(DateTime inicio, int minutos) {
    final d = inicio.add(Duration(minutes: minutos));
    return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  }

  Future<void> elegir(
    BuildContext context,
    Map<String, dynamic> ventana,
  ) async {
    final inicio = DateTime.parse(ventana['inicio_en']);
    final fin = DateTime.parse(ventana['fin_en']);
    final local = civil(ventana['inicio_local']);
    final destino = civil(ventana['inicio_destino_local']);
    final minutos = fin.difference(inicio).inMinutes;
    final dia = civil(datos!['fecha']);
    final limiteSalida =
        DateTime.utc(
          dia.year,
          dia.month,
          dia.day + 1,
        ).difference(local).inMinutes -
        1;
    final cambiaZona =
        civil(ventana['fin_local']).difference(local).inMinutes != minutos ||
        civil(ventana['fin_destino_local']).difference(destino).inMinutes !=
            minutos;
    if (minutos < 1 || limiteSalida < 0) return;
    if (cambiaZona) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cambio de hora estacional'),
          content: const Text(
            'Este intervalo incluye un cambio de hora. Elige salida y llegada con los calendarios del formulario; el servidor comprobará los instantes exactos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    var rango = RangeValues(0, minutos.clamp(1, 60).toDouble());
    final elegido = await showDialog<RangeValues>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, actualizar) {
          final salida = local.add(Duration(minutes: rango.start.round()));
          final llegada = destino.add(Duration(minutes: rango.end.round()));
          return DialogoAerotech(
            title: 'Elige un horario libre',
            subtitle:
                'Ajusta el inicio y el final dentro del intervalo disponible.',
            icon: Icons.schedule,
            maxWidth: 620,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: rango.end > rango.start
                    ? () => Navigator.pop(context, rango)
                    : null,
                child: const Text('Aplicar horario'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Salida · ${datos!["zona_origen"]}\n${horario(salida.toIso8601String())}',
                ),
                RangeSlider(
                  min: 0,
                  max: minutos.toDouble(),
                  divisions: minutos,
                  values: rango,
                  labels: RangeLabels(
                    horario(salida.toIso8601String()),
                    horario(llegada.toIso8601String()),
                  ),
                  onChanged: (valor) {
                    final inicioMin = valor.start
                        .round()
                        .clamp(0, limiteSalida)
                        .clamp(0, minutos - 1)
                        .toDouble();
                    final finMin = valor.end
                        .round()
                        .clamp(inicioMin.toInt() + 1, minutos)
                        .toDouble();
                    actualizar(() => rango = RangeValues(inicioMin, finMin));
                  },
                ),
                Text(
                  'Llegada · ${datos!["zona_destino"]}\n${horario(llegada.toIso8601String())}',
                ),
                const SizedBox(height: 12),
                Text('Duración: ${(rango.end - rango.start).round()} minutos'),
              ],
            ),
          );
        },
      ),
    );
    if (elegido != null) {
      onSeleccionar(
        sumarCivil(local, elegido.start.round()),
        sumarCivil(destino, elegido.end.round()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ventanas = lista('ventanas')
        .where(
          (v) => v['inicio_local'].toString().startsWith(
            datos?['fecha']?.toString() ?? '?',
          ),
        )
        .toList();
    final ocupados = lista('ocupados');
    final conflictos = lista('conflictos');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.airplane_ticket_outlined),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Disponibilidad del avión',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar horarios del avión',
              onPressed: cargando || bloqueado ? null : onActualizar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (cargando) const LinearProgressIndicator(),
        if (error != null) PanelMensaje(error!, error: true),
        if (datos == null && error == null && !cargando)
          const Text(
            'Elige un avión, una ruta y la fecha de salida para consultar sus horarios libres.',
          ),
        if (datos != null) ...[
          Text('Horarios de salida · ${datos!["zona_origen"]}'),
          if (datos!['disponible'] == false)
            const PanelMensaje(
              'El avión ya tiene otro vuelo en ese horario. Elige un intervalo libre.',
              error: true,
            ),
          for (final c in conflictos)
            Text(
              '${c["fecha"]} · ${c["codigo"]} · ${horario(c["inicio_local"])} – ${horario(c["fin_local"])}',
            ),
          if (ocupados.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Intervalos ocupados',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final o in ocupados)
              Text(
                '${o["codigo"]} · ${horario(o["inicio_local"])} – ${horario(o["fin_local"])}',
              ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Intervalos libres',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (ventanas.isEmpty)
            const Text('No hay intervalos libres para esta fecha.'),
          for (final v in ventanas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    '${horario(v["inicio_local"])} – ${horario(v["fin_local"])}',
                  ),
                  OutlinedButton.icon(
                    onPressed: bloqueado || cargando
                        ? null
                        : () => elegir(context, v),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Elegir intervalo'),
                  ),
                ],
              ),
            ),
          const Text(
            'La disponibilidad se vuelve a comprobar al guardar; consultar no bloquea el avión.',
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
