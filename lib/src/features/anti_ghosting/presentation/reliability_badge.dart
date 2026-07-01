import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Badge POSITIVO "Responde con intención" (Attra Clear §8). Nunca muestra
/// porcentajes, ranking ni nada negativo. Solo se pinta si el backend marcó
/// `hasReliabilityBadge` y el flag está activo.
class ReliabilityBadge extends StatelessWidget {
  const ReliabilityBadge({super.key, this.compact = false});

  /// Versión compacta (solo chip) para cabeceras/listas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.verified_rounded, size: 14, color: AppColors.gold),
          const SizedBox(width: 5),
          Text(
            'Responde con intención',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: compact ? 11 : 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    if (compact) return chip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        chip,
        const SizedBox(height: 6),
        Text(
          'Suele responder y cerrar conversaciones con respeto.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}
