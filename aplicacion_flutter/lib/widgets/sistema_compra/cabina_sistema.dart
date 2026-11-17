import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/checkout_operacion.dart';

class CabinaSistema extends StatelessWidget {
  const CabinaSistema({
    super.key,
    required this.clases,
    required this.asientos,
    required this.seleccionados,
    required this.onChanged,
    this.bloqueada = false,
  });
  final List<Map<String, dynamic>> clases, asientos;
  final Set<String> seleccionados;
  final ValueChanged<String> onChanged;
  final bool bloqueada;
  @override
  Widget build(BuildContext context) {
    final porCodigo = {for (final s in asientos) s['codigo'].toString(): s};
    return Column(
      children: [
        const Text('Doble clic o Enter para elegir · Gris: no disponible'),
        const SizedBox(height: 12),
        for (final clase in clases) ...[
          Text(
            '${clase['nombre']} · ${clase['codigo']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                for (
                  var fila = (clase['fila_inicio'] as num).toInt();
                  fila <
                      (clase['fila_inicio'] as num) + (clase['filas'] as num);
                  fila++
                )
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 32, child: Text('$fila')),
                        for (final grupo in clase['columnas'] as List) ...[
                          for (final columna in grupo as List)
                            _asiento(
                              context,
                              porCodigo['$fila$columna'],
                              '$fila$columna',
                            ),
                          const SizedBox(width: 22),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Seleccionados: ${seleccionados.isEmpty ? 'ninguno' : seleccionados.join(', ')}',
        ),
      ],
    );
  }

  Widget _asiento(BuildContext context, Map<String, dynamic>? s, String code) {
    final libre = s?['estado'] == 'libre' && !bloqueada;
    final selected = seleccionados.contains(code);
    void elegir() {
      if (libre) onChanged(code);
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        label:
            'Asiento $code, ${s?['clase_nombre'] ?? ''}, ${s?['estado'] ?? 'no disponible'}, ${dinero(s?['precio_centavos'])}',
        button: true,
        enabled: libre,
        selected: selected,
        onTap: libre ? elegir : null,
        child: Focus(
          canRequestFocus: libre,
          onKeyEvent: (_, event) {
            if (libre &&
                event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              elegir();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Tooltip(
            message:
                '$code · ${s?['clase_nombre'] ?? ''} · ${dinero(s?['precio_centavos'])} · ${s?['estado'] ?? 'no disponible'}',
            child: GestureDetector(
              key: ValueKey('asiento-$code'),
              onDoubleTap: libre ? elegir : null,
              child: Container(
                width: 48,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.teal
                      : libre
                      ? const Color(0xffe0f4fa)
                      : Colors.blueGrey.shade200,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected ? Colors.teal.shade900 : Colors.blueGrey,
                  ),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
