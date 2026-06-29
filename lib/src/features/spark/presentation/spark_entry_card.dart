import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../data/spark_service.dart';
import '../domain/spark_session.dart';
import 'spark_game_screen.dart';

/// Card opcional dentro del chat para iniciar/continuar Attra Spark. Solo se
/// renderiza si la feature está habilitada (lo decide quien la inserta). Si no
/// hay sesión viva, ofrece invitar; si la hay, ofrece aceptar/continuar.
///
/// No bloquea el chat: es un añadido por encima de la conversación normal.
class SparkEntryCard extends StatelessWidget {
  const SparkEntryCard({
    super.key,
    required this.service,
    required this.matchId,
    required this.currentUid,
    required this.otherUid,
    required this.otherName,
    this.onReport,
    this.onUseQuestion,
  });

  final SparkService service;
  final String matchId;
  final String currentUid;
  final String otherUid;
  final String otherName;
  final Future<void> Function()? onReport;
  final void Function(String question)? onUseQuestion;

  void _openGame(BuildContext context, String sessionId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SparkGameScreen(
        service: service,
        matchId: matchId,
        sessionId: sessionId,
        currentUid: currentUid,
        otherName: otherName,
        onReport: onReport,
        onUseQuestion: onUseQuestion,
        onOpenChat: () {/* el chat ya está debajo */},
      ),
    ));
  }

  Future<void> _invite(BuildContext context) async {
    try {
      final String id = await service.invite(
        matchId: matchId,
        hostUid: currentUid,
        guestUid: otherUid,
      );
      if (context.mounted) _openGame(context, id);
    } on SparkAlreadyPlayedException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SparkSession?>(
      stream: service.watchActiveSession(matchId),
      builder: (BuildContext context, AsyncSnapshot<SparkSession?> snap) {
        final SparkSession? s = snap.data;

        // Si hay sesión viva, ofrece aceptar/continuar. Si no, miramos si ya se
        // jugó alguna vez: Spark es un rompehielos de un solo uso por match.
        if (s == null) return _NoActiveSparkCard(parent: this);

        final bool iAccepted = s.participants[currentUid]?.accepted ?? false;
        final bool incoming = s.invitedBy != currentUid && !iAccepted;

        if (s.status == SparkStatus.waiting && incoming) {
          return _Card(
            title: '$otherName te invita a Attra Spark',
            subtitle: 'Un juego rápido para conoceros. ¿Jugamos?',
            ctaLabel: 'Aceptar y jugar',
            ctaIcon: Icons.play_arrow_rounded,
            onCta: () => _openGame(context, s.id),
          );
        }

        // Sesión viva en la que ya participo (esperando o activa): continuar.
        return _Card(
          title: 'Attra Spark en curso',
          subtitle: s.status == SparkStatus.active
              ? 'Ronda ${s.currentRound + 1} de ${s.totalRounds}'
              : 'Esperando a $otherName…',
          ctaLabel: 'Continuar',
          ctaIcon: Icons.arrow_forward_rounded,
          onCta: () => _openGame(context, s.id),
        );
      },
    );
  }
}

class _NoActiveSparkCard extends StatelessWidget {
  const _NoActiveSparkCard({required this.parent});

  final SparkEntryCard parent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SparkSession?>(
      stream: parent.service.watchAnySession(parent.matchId),
      builder: (BuildContext context, AsyncSnapshot<SparkSession?> snap) {
        final SparkSession? any = snap.data;
        if (any == null) {
          return _Card(
            title: 'Attra Spark',
            subtitle: 'Jugad 5 minutos para romper el hielo. Opcional.',
            ctaLabel: 'Jugar 5 minutos',
            ctaIcon: Icons.bolt_rounded,
            onCta: () => parent._invite(context),
          );
        }
        if (any.status == SparkStatus.completed) {
          return _Card(
            title: 'Attra Spark completado',
            subtitle: 'Ya usasteis este rompehielos. Podéis volver al resumen.',
            ctaLabel: 'Ver resumen',
            ctaIcon: Icons.celebration_rounded,
            onCta: () => parent._openGame(context, any.id),
          );
        }
        return const _Card(
          title: 'Attra Spark ya usado',
          subtitle: 'Este rompehielos solo se puede jugar una vez por match.',
          ctaLabel: 'Completado',
          ctaIcon: Icons.lock_outline_rounded,
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.ctaIcon,
    this.onCta,
  });

  final String title;
  final String subtitle;
  final String ctaLabel;
  final IconData ctaIcon;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[const Color(0x33E5384E), context.colors.surface],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.attraRed.withValues(alpha: 0.18),
            ),
            child: const Icon(Icons.bolt_rounded, color: AppColors.attraRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onCta,
            icon: Icon(ctaIcon, size: 18),
            label: Text(ctaLabel),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.attraRed,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}
