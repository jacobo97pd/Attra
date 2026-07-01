import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../domain/nudge_tier.dart';

/// Acción elegida en una [AntiGhostingNudgeCard].
enum NudgeAction { reply, proposePlan, closeGracefully, remindLater }

/// Tarjeta de recordatorio dentro del chat (Attra Clear §5/§15). Orienta sin
/// presionar: siempre incluye "Recordármelo luego" y nunca obliga a responder.
class AntiGhostingNudgeCard extends StatelessWidget {
  const AntiGhostingNudgeCard({
    super.key,
    required this.tier,
    required this.onAction,
    this.canProposePlan = false,
    this.canClose = false,
  });

  final NudgeTier tier;
  final ValueChanged<NudgeAction> onAction;
  final bool canProposePlan;
  final bool canClose;

  String get _title {
    switch (tier) {
      case NudgeTier.cold:
        return 'Esta conversación se ha enfriado';
      case NudgeTier.firm:
        return 'Lleva un tiempo esperando';
      case NudgeTier.gentle:
      case NudgeTier.none:
        return '¿Quieres seguir esta conversación?';
    }
  }

  String get _body {
    switch (tier) {
      case NudgeTier.cold:
        return 'Puedes cerrarla con respeto para no dejar a la otra persona '
            'en el aire.';
      case NudgeTier.firm:
        return 'Puedes responder o cerrarla con elegancia.';
      case NudgeTier.gentle:
      case NudgeTier.none:
        return 'Te toca responder. ¿Sigues con ganas?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> actions = <Widget>[
      if (tier != NudgeTier.cold)
        _Action(
          label: 'Responder',
          primary: true,
          onTap: () => onAction(NudgeAction.reply),
        ),
      if (tier == NudgeTier.gentle && canProposePlan)
        _Action(
          label: 'Proponer plan',
          onTap: () => onAction(NudgeAction.proposePlan),
        ),
      if (canClose)
        _Action(
          label: 'Cerrar con elegancia',
          onTap: () => onAction(NudgeAction.closeGracefully),
        ),
      _Action(
        label: 'Recordármelo luego',
        muted: true,
        onTap: () => onAction(NudgeAction.remindLater),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.schedule_rounded,
                  size: 18, color: AppColors.attraRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_body,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.colors.textSecondary, height: 1.3)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.muted = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final Color bg = primary
        ? AppColors.attraRed
        : (muted ? Colors.transparent : context.colors.surfaceHigh);
    final Color fg = primary
        ? Colors.white
        : (muted ? context.colors.textMuted : context.colors.textPrimary);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: muted
                ? null
                : Border.all(
                    color: primary
                        ? Colors.transparent
                        : context.colors.surfaceLine),
          ),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
