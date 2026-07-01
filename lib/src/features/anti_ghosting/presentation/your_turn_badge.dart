import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Píldora "Te toca responder" para la bandeja "Tu turno" (Attra Clear §1/§15).
/// Opcionalmente muestra cuánto lleva esperando ("· hace 18 h").
class YourTurnBadge extends StatelessWidget {
  const YourTurnBadge({super.key, this.waitingLabel});

  /// Texto de espera ya formateado (p. ej. "hace 18 h"). Si es null, solo muestra
  /// "Te toca responder".
  final String? waitingLabel;

  @override
  Widget build(BuildContext context) {
    final String text = waitingLabel == null
        ? 'Te toca responder'
        : 'Te toca responder · $waitingLabel';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.attraRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.reply_rounded, size: 13, color: AppColors.attraRed),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.attraRed,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
