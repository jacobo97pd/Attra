import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/date_plan_service.dart';
import '../domain/date_plan.dart';

/// Attra Plans — tira sobre el composer del chat. Muestra la propuesta activa
/// del match con VOTACIÓN entre ambos (Fase 4): cada uno elige su opción
/// favorita y, cuando coinciden, la propuesta queda confirmada.
class DatePlansStrip extends StatelessWidget {
  const DatePlansStrip({
    super.key,
    required this.matchId,
    required this.chatId,
    required this.currentUid,
    required this.service,
  });

  final String matchId;
  final String chatId;
  final String currentUid;
  final DatePlanService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatePlanProposal>>(
      stream: service.observePlans(matchId),
      builder:
          (BuildContext context, AsyncSnapshot<List<DatePlanProposal>> snap) {
        final List<DatePlanProposal> plans =
            snap.data ?? const <DatePlanProposal>[];
        // Prioriza una propuesta confirmada reciente; si no, la última abierta.
        DatePlanProposal? confirmed;
        DatePlanProposal? open;
        for (final DatePlanProposal p in plans) {
          if (p.isExpired) continue;
          if (p.status.isConfirmed && confirmed == null) confirmed = p;
          if (p.isActionable && open == null) open = p;
        }
        final DatePlanProposal? plan = confirmed ?? open;
        if (plan == null) return const SizedBox.shrink();
        if (plan.status.isConfirmed) {
          return _ConfirmedCard(plan: plan);
        }
        return _VotingCard(
          plan: plan,
          chatId: chatId,
          currentUid: currentUid,
          service: service,
        );
      },
    );
  }
}

/// Tarjeta de votación: opciones con botón "Me apunto" + estado del match.
class _VotingCard extends StatefulWidget {
  const _VotingCard({
    required this.plan,
    required this.chatId,
    required this.currentUid,
    required this.service,
  });

  final DatePlanProposal plan;
  final String chatId;
  final String currentUid;
  final DatePlanService service;

  @override
  State<_VotingCard> createState() => _VotingCardState();
}

class _VotingCardState extends State<_VotingCard> {
  bool _busy = false;

  String get _otherUid => widget.plan.users
      .firstWhere((String u) => u != widget.currentUid, orElse: () => '');

  Future<void> _vote(String optionId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.voteOption(
        chatId: widget.chatId,
        planId: widget.plan.id,
        optionId: optionId,
      );
    } on DatePlanServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo enviar tu voto.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service
          .rejectProposal(chatId: widget.chatId, planId: widget.plan.id);
    } catch (_) {
      _snack('No se pudo actualizar la propuesta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DatePlanProposal plan = widget.plan;
    final String? myVote = plan.votesByUser[widget.currentUid];
    final String? otherVote = plan.votesByUser[_otherUid];
    final bool mine = plan.createdBy == widget.currentUid;

    // Mensaje de estado del match.
    String statusLine;
    if (otherVote == null) {
      statusLine = myVote == null
          ? 'Elegid vuestra opción favorita.'
          : 'Ya has votado. Falta tu match.';
    } else if (myVote == null) {
      statusLine = 'Tu match ya ha votado. Elige la tuya.';
    } else if (myVote == otherVote) {
      statusLine = '¡Coincidís!';
    } else {
      statusLine = 'Habéis elegido distinto. Poneos de acuerdo 🙂';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.event_available,
                  size: 18, color: theme.colorScheme.primary),
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
            const SizedBox(height: 4),
            Text(plan.generatedReason, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          for (final DatePlanOption o in plan.options)
            _OptionVoteRow(
              option: o,
              theme: theme,
              chosenByMe: myVote == o.id,
              chosenByOther: otherVote == o.id,
              enabled: !_busy,
              onVote: () => _vote(o.id),
            ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(statusLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _busy ? null : _reject,
                child: const Text('No me interesa'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionVoteRow extends StatelessWidget {
  const _OptionVoteRow({
    required this.option,
    required this.theme,
    required this.chosenByMe,
    required this.chosenByOther,
    required this.enabled,
    required this.onVote,
  });

  final DatePlanOption option;
  final ThemeData theme;
  final bool chosenByMe;
  final bool chosenByOther;
  final bool enabled;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final List<String> meta = <String>[
      if (option.rating != null)
        '⭐ ${option.rating!.toStringAsFixed(1)}'
            '${option.reviewCount != null ? ' · ${option.reviewCount}' : ''}',
      if (option.suggestedDateTime != null) _fmt(option.suggestedDateTime!),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: chosenByMe
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: chosenByMe
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(option.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (option.placeName.isNotEmpty)
                  Text(option.placeName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                if (meta.isNotEmpty)
                  Text(meta.join('  ·  '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                if (chosenByOther)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Tu match eligió esta',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          chosenByMe
              ? Icon(Icons.check_circle,
                  color: theme.colorScheme.primary, size: 26)
              : OutlinedButton(
                  onPressed: enabled ? onVote : null,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Me apunto'),
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

/// Tarjeta de plan CONFIRMADO: ambos eligieron la misma opción.
class _ConfirmedCard extends StatelessWidget {
  const _ConfirmedCard({required this.plan});

  final DatePlanProposal plan;

  Future<void> _openMaps(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DatePlanOption? o = plan.selectedOption;
    final String when =
        o?.suggestedDateTime != null ? _fmt(o!.suggestedDateTime!) : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.celebration,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('¡Plan confirmado!',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(o?.title ?? 'Vuestro plan',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (o != null && o.placeName.isNotEmpty)
            Text(o.placeName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          if (when.isNotEmpty || plan.zone.isNotEmpty)
            Text(
              <String>[
                if (when.isNotEmpty) when,
                if (plan.zone.isNotEmpty) plan.zone,
              ].join('  ·  '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          if (o != null && o.mapsUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openMaps(o.mapsUrl),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Abrir en Maps'),
            ),
          ],
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
