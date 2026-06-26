import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../domain/match_journey.dart';

/// Card del Match Journey en el chat (Fase 8): muestra el estado del match y UNA
/// sugerencia contextual (CTA). No bloquea el chat, es cerrable y elegante.
///
/// La UI decide qué hacer con cada CTA via callbacks; si un callback es null,
/// esa CTA no se ofrece (p.ej. si Date Builder/Spark están desactivados).
class MatchJourneyCard extends StatelessWidget {
  const MatchJourneyCard({
    super.key,
    required this.journey,
    required this.otherName,
    this.onIcebreaker,
    this.onQuickGame,
    this.onProposePlan,
    this.onReactivate,
    required this.onDismiss,
  });

  final MatchJourney journey;
  final String otherName;
  final VoidCallback? onIcebreaker;
  final VoidCallback? onQuickGame;
  final VoidCallback? onProposePlan;
  final VoidCallback? onReactivate;
  final VoidCallback onDismiss;

  /// Resuelve (texto CTA, acción) según el estado. Devuelve null si no hay CTA
  /// disponible (callback ausente) -> entonces no se muestra la card.
  ({String label, IconData icon, VoidCallback action})? _cta() {
    switch (journey.suggestedCta) {
      case MatchJourneyCta.launchIcebreaker:
        if (onIcebreaker != null) {
          return (
            label: 'Romper el hielo',
            icon: Icons.ac_unit_rounded,
            action: onIcebreaker!
          );
        }
        return null;
      case MatchJourneyCta.playQuickGame:
        if (onQuickGame != null) {
          return (
            label: 'Jugar algo rápido',
            icon: Icons.casino_rounded,
            action: onQuickGame!
          );
        }
        if (onIcebreaker != null) {
          return (
            label: 'Lanzar una pregunta',
            icon: Icons.ac_unit_rounded,
            action: onIcebreaker!
          );
        }
        return null;
      case MatchJourneyCta.proposePlan:
        if (onProposePlan != null) {
          return (
            label: 'Proponer un plan',
            icon: Icons.calendar_today_rounded,
            action: onProposePlan!
          );
        }
        return null;
      case MatchJourneyCta.reactivate:
        final VoidCallback? cb = onReactivate ?? onIcebreaker;
        if (cb != null) {
          return (
            label: 'Reactivar conversación',
            icon: Icons.bolt_rounded,
            action: cb
          );
        }
        return null;
      case MatchJourneyCta.none:
        return null;
    }
  }

  String get _subtitle {
    switch (journey.suggestedCta) {
      case MatchJourneyCta.launchIcebreaker:
        return 'Da el primer paso con $otherName.';
      case MatchJourneyCta.playQuickGame:
        return 'Un juego rápido para coger confianza.';
      case MatchJourneyCta.proposePlan:
        return 'Va bien la cosa. ¿Y si quedáis?';
      case MatchJourneyCta.reactivate:
        return 'Este match se está enfriando.';
      case MatchJourneyCta.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({String label, IconData icon, VoidCallback action})? cta = _cta();
    if (cta == null) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
            color: journey.coolingDown
                ? AppColors.gold.withValues(alpha: 0.5)
                : AppColors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (journey.coolingDown ? AppColors.gold : AppColors.attraRed)
                  .withValues(alpha: 0.16),
            ),
            child: Icon(cta.icon,
                size: 19,
                color:
                    journey.coolingDown ? AppColors.gold : AppColors.attraRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(journey.label,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4)),
                const SizedBox(height: 1),
                Text(_subtitle,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: cta.action,
            child: Text(cta.label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Ocultar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textMuted),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
