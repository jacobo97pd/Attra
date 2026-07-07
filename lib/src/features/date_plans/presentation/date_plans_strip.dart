import 'package:flutter/material.dart';

import '../data/date_plan_service.dart';
import '../domain/date_plan.dart';

/// Attra Plans — tira compacta sobre el composer del chat que muestra la última
/// propuesta ABIERTA del match con sus opciones.
///
/// Fase 1: solo LECTURA (render de la propuesta creada manualmente). La votación
/// y confirmación entre ambos (Fase 4) se enchufan aquí después mediante
/// callbacks, sin rehacer el widget.
class DatePlansStrip extends StatelessWidget {
  const DatePlansStrip({
    super.key,
    required this.matchId,
    required this.currentUid,
    required this.service,
  });

  final String matchId;
  final String currentUid;
  final DatePlanService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatePlanProposal>>(
      stream: service.observePlans(matchId),
      builder: (BuildContext context,
          AsyncSnapshot<List<DatePlanProposal>> snap) {
        final List<DatePlanProposal> plans =
            snap.data ?? const <DatePlanProposal>[];
        DatePlanProposal? plan;
        for (final DatePlanProposal p in plans) {
          if (p.isActionable) {
            plan = p;
            break;
          }
        }
        if (plan == null) return const SizedBox.shrink();
        return _ProposalCard(plan: plan, currentUid: currentUid);
      },
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.plan, required this.currentUid});

  final DatePlanProposal plan;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool mine = plan.createdBy == currentUid;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.event_available, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mine ? 'Tu propuesta de plan' : 'Te proponen un plan',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (plan.zone.isNotEmpty)
                Text(plan.zone,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
          if (plan.generatedReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(plan.generatedReason, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          for (final DatePlanOption o in plan.options)
            _OptionRow(option: o, theme: theme),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.theme});

  final DatePlanOption option;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final List<String> meta = <String>[
      if (option.rating != null)
        '⭐ ${option.rating!.toStringAsFixed(1)}'
            '${option.reviewCount != null ? ' · ${option.reviewCount} reseñas' : ''}',
      if (option.suggestedDateTime != null) _fmt(option.suggestedDateTime!),
      if (option.area.isNotEmpty) option.area,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(option.title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          if (option.placeName.isNotEmpty)
            Text(option.placeName,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          if (meta.isNotEmpty)
            Text(meta.join('  ·  '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          if (option.whyItFits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(option.whyItFits,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final DateTime l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} · '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
