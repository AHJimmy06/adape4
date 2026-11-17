import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/aerotech_theme.dart';

/// Demonstration layout, not the aircraft's inventory or assigned seating.
class CabinaAsientos extends StatelessWidget {
  const CabinaAsientos({
    super.key,
    required this.selectedSeats,
    required this.onToggle,
    required this.maxSeleccion,
    this.enabled = true,
  });
  final Set<String> selectedSeats;
  final ValueChanged<String> onToggle;
  final int maxSeleccion;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final available = maxSeleccion < 0 ? 0 : maxSeleccion;
    final rows = (available + 3) ~/ 4;
    return SizedBox(
      height: 460,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(child: CustomPaint(painter: _AircraftPainter())),
              Positioned(
                top: 62,
                width: width.clamp(0, 220).toDouble(),
                child: Column(
                  children: [
                    const Icon(
                      Icons.flight_class,
                      color: AerotechTheme.blue,
                      size: 22,
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text('A'),
                        Text('B'),
                        SizedBox(width: 16),
                        Text('C'),
                        Text('D'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 288,
                      child: ListView.builder(
                        key: const ValueKey('cabin-rows'),
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemExtent: 48,
                        itemCount: rows,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              for (var column = 0; column < 5; column++)
                                if (column == 2)
                                  SizedBox(
                                    width: 20,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AerotechTheme.textSecondary,
                                      ),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child:
                                        index * 4 +
                                                (column < 2
                                                    ? column
                                                    : column - 1) <
                                            available
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                            ),
                                            child: _seat(
                                              index + 1,
                                              'AB CD'[column],
                                              available,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'CABINA ILUSTRATIVA',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.5,
                        color: AerotechTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _seat(int row, String letter, int available) {
    final label = '$row$letter';
    final selected = selectedSeats.contains(label);
    return _SeatButton(
      key: ValueKey('seat-$label'),
      label: label,
      selected: selected,
      onToggle: enabled && (selected || selectedSeats.length < available)
          ? () => onToggle(label)
          : null,
    );
  }
}

class _SeatButton extends StatefulWidget {
  const _SeatButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onToggle,
  });
  final String label;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  State<_SeatButton> createState() => _SeatButtonState();
}

class _SeatButtonState extends State<_SeatButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onToggle != null,
    onShowFocusHighlight: (value) => setState(() => _focused = value),
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onToggle?.call();
          return null;
        },
      ),
    },
    child: Semantics(
      label: 'Asiento ${widget.label}, preferencia visual',
      hint: 'Doble clic para marcar o desmarcar; con teclado, Enter o espacio.',
      selected: widget.selected,
      button: true,
      enabled: widget.onToggle != null,
      onTap: widget.onToggle,
      excludeSemantics: true,
      child: Material(
        color: widget.selected ? AerotechTheme.navy : const Color(0xFFE0F3F5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _focused ? AerotechTheme.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          canRequestFocus: false,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(8),
          onDoubleTap: widget.onToggle,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.selected ? Colors.white : AerotechTheme.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AircraftPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final half = (size.width * .43).clamp(0, 122).toDouble();
    final wings = Path()
      ..moveTo(center - half, 180)
      ..lineTo(4, 300)
      ..lineTo(4, 325)
      ..lineTo(center - half, 275)
      ..lineTo(center + half, 275)
      ..lineTo(size.width - 4, 325)
      ..lineTo(size.width - 4, 300)
      ..lineTo(center + half, 180)
      ..close();
    canvas.drawPath(wings, Paint()..color = const Color(0xFFB6D2E3));
    final body = Path()
      ..moveTo(center, 4)
      ..cubicTo(center + half, 8, center + half, 70, center + half, 130)
      ..lineTo(center + half, 365)
      ..quadraticBezierTo(center + half, 440, center, 454)
      ..quadraticBezierTo(center - half, 440, center - half, 365)
      ..lineTo(center - half, 130)
      ..cubicTo(center - half, 70, center - half, 8, center, 4)
      ..close();
    canvas.drawShadow(
      body,
      AerotechTheme.navy.withValues(alpha: .18),
      8,
      false,
    );
    canvas.drawPath(body, Paint()..color = Colors.white);
    canvas.drawPath(
      body,
      Paint()
        ..color = AerotechTheme.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(center, 48), width: 50, height: 35),
      3.5,
      2.4,
      false,
      Paint()
        ..color = AerotechTheme.navy
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AircraftPainter oldDelegate) => false;
}
