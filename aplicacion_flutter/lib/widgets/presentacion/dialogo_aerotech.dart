import 'package:flutter/material.dart';

import '../../theme/aerotech_theme.dart';

/// Solo presentación: no modifica estados ni fechas del servidor.
String estadoLegible(dynamic value) => switch (value?.toString()) {
  'preparando_pago' => 'Preparando pago',
  'pendiente_pago' => 'Pendiente de pago',
  'revision_pago' || 'revision' => 'En revisión',
  'pagado' => 'Pago confirmado · reserva emitida',
  'expirado' => 'Pedido vencido',
  'cancelado' => 'Cancelado',
  'activa' || 'activo' => 'Activo',
  'parcial' || 'parcialmente_cancelada' => 'Cancelación parcial',
  'cancelada' => 'Cancelada',
  'pendiente' || 'pending' || 'reembolso_pendiente' => 'Reembolso pendiente',
  'fallida' || 'fallido' || 'failed' => 'Reembolso no completado',
  'completada' => 'Reembolso confirmado',
  _ => 'Estado por verificar',
};

/// Los instantes con zona se muestran en UTC o en hora de Ecuador (UTC−5).
/// Los horarios civiles conservan su zona, sin inferir conversiones IANA.
String fechaLegible(dynamic value, {String? zona, bool horaEcuador = false}) {
  final raw = value?.toString() ?? '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return 'Fecha por confirmar';
  final zoned = RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(raw);
  final date = zoned
      ? parsed.toUtc().subtract(Duration(hours: horaEcuador ? 5 : 0))
      : parsed;
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final hour =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  final label = zoned
      ? (horaEcuador ? 'Ecuador (UTC−5)' : 'UTC')
      : (zona?.isNotEmpty == true ? zona! : 'zona no especificada');
  return '${date.day} ${months[date.month - 1]} ${date.year} · $hour $label';
}

class DialogoAerotech extends StatelessWidget {
  const DialogoAerotech({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    required this.actions,
    this.eyebrow = 'AEROTECH',
    this.maxWidth = 680,
  });
  final String title, subtitle, eyebrow;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AerotechTheme.surface,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    shape: AerotechTheme.cardShape,
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EncabezadoDialogo(
                    title: title,
                    subtitle: subtitle,
                    eyebrow: eyebrow,
                    icon: icon,
                  ),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AerotechTheme.inputFill,
              border: Border(top: BorderSide(color: AerotechTheme.border)),
            ),
            padding: const EdgeInsets.all(16),
            child: AccionesDialogo(children: actions),
          ),
        ],
      ),
    ),
  );
}

class EncabezadoDialogo extends StatelessWidget {
  const EncabezadoDialogo({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.eyebrow = 'AEROTECH',
  });
  final String title, subtitle, eyebrow;
  final IconData icon;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 480;
      final iconBadge = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AerotechTheme.blue.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AerotechTheme.blue, size: 28),
      );
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: AerotechTheme.blue,
              fontSize: 11,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: AerotechTheme.navy,
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AerotechTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      );
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            iconBadge,
            const SizedBox(width: 18),
            Expanded(child: text),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [iconBadge, const SizedBox(height: 16), text],
      );
    },
  );
}

class AccionesDialogo extends StatelessWidget {
  const AccionesDialogo({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 420;
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 10,
        children: [
          for (final child in children)
            SizedBox(width: narrow ? constraints.maxWidth : null, child: child),
        ],
      );
    },
  );
}

class PanelMensaje extends StatelessWidget {
  const PanelMensaje(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : AerotechTheme.blue;
    return Semantics(
      liveRegion: error,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          border: Border.all(color: color.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado(this.state, {super.key});
  final dynamic state;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AerotechTheme.blue.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AerotechTheme.blue.withValues(alpha: .16)),
    ),
    child: Text(
      estadoLegible(state),
      style: const TextStyle(
        color: AerotechTheme.blue,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
