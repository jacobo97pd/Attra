import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../data/spark_service.dart';
import '../domain/spark_session.dart';
import 'spark_game_screen.dart';

/// Sugerencia COMPACTA (una línea) dentro del chat para iniciar/continuar Attra
/// Spark. No bloquea el chat ni ocupa media pantalla: es una barra fina y
/// cerrable ([onDismiss]). Si no hay sesión viva ofrece invitar; si la hay,
/// aceptar/continuar.
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
    this.onDismiss,
  });

  final SparkService service;
  final String matchId;
  final String currentUid;
  final String otherUid;
  final String otherName;
  final Future<void> Function()? onReport;
  final void Function(String question)? onUseQuestion;

  /// Si se pasa, muestra una ✕ para ocultar la sugerencia esta sesión.
  final VoidCallback? onDismiss;

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
        if (s == null) return _NoActiveSpark(parent: this);

        final bool iAccepted = s.participants[currentUid]?.accepted ?? false;
        final bool incoming = s.invitedBy != currentUid && !iAccepted;

        if (s.status == SparkStatus.waiting && incoming) {
          return _SparkBar(
            label: '$otherName te reta a Attra Spark',
            ctaLabel: 'Aceptar',
            onCta: () => _openGame(context, s.id),
            onClose: onDismiss,
          );
        }
        return _SparkBar(
          label: s.status == SparkStatus.active
              ? 'Spark en curso · ronda ${s.currentRound + 1}/${s.totalRounds}'
              : 'Esperando a $otherName…',
          ctaLabel: 'Continuar',
          onCta: () => _openGame(context, s.id),
          onClose: onDismiss,
        );
      },
    );
  }
}

class _NoActiveSpark extends StatelessWidget {
  const _NoActiveSpark({required this.parent});

  final SparkEntryCard parent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SparkSession?>(
      stream: parent.service.watchAnySession(parent.matchId),
      builder: (BuildContext context, AsyncSnapshot<SparkSession?> snap) {
        final SparkSession? any = snap.data;
        if (any == null) {
          return _SparkBar(
            label: 'Rompe el hielo con Attra Spark · 5 min',
            ctaLabel: 'Jugar',
            onCta: () => parent._invite(context),
            onClose: parent.onDismiss,
          );
        }
        if (any.status == SparkStatus.completed) {
          return _SparkBar(
            label: 'Attra Spark completado',
            ctaLabel: 'Resumen',
            onCta: () => parent._openGame(context, any.id),
            onClose: parent.onDismiss,
          );
        }
        // Ya usado (terminal no completado): sugerencia mínima, cerrable.
        return _SparkBar(
          label: 'Attra Spark ya usado',
          onClose: parent.onDismiss,
        );
      },
    );
  }
}

/// Barra fina (una línea): bolt + texto + CTA opcional + cerrar opcional.
class _SparkBar extends StatelessWidget {
  const _SparkBar({
    required this.label,
    this.ctaLabel,
    this.onCta,
    this.onClose,
  });

  final String label;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.only(left: 12, right: 4),
      height: 42,
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt_rounded, size: 18, color: AppColors.attraRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (ctaLabel != null && onCta != null)
            TextButton(
              onPressed: onCta,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.attraRed,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(ctaLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: context.colors.textMuted),
              visualDensity: VisualDensity.compact,
              tooltip: 'Ocultar',
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
