import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_buttons.dart';
import '../data/spark_service.dart';
import '../domain/spark_round.dart';
import '../domain/spark_session.dart';
import 'spark_summary_sheet.dart';

/// Sala privada del juego Attra Spark. Stream del doc de sesión + heartbeat de
/// presencia + ticker de countdown. Renderiza según estado y ronda actual.
class SparkGameScreen extends StatefulWidget {
  const SparkGameScreen({
    super.key,
    required this.service,
    required this.matchId,
    required this.sessionId,
    required this.currentUid,
    required this.otherName,
    this.onReport,
    this.onOpenChat,
    this.onUseQuestion,
  });

  final SparkService service;
  final String matchId;
  final String sessionId;
  final String currentUid;
  final String otherName;

  /// Reporta al otro usuario (reusa el flujo de seguridad del chat).
  final Future<void> Function()? onReport;

  /// Abre el chat normal (al terminar o salir).
  final VoidCallback? onOpenChat;

  /// Prefilla el input del chat con una pregunta sugerida del resumen.
  final void Function(String question)? onUseQuestion;

  @override
  State<SparkGameScreen> createState() => _SparkGameScreenState();
}

class _SparkGameScreenState extends State<SparkGameScreen> {
  late final List<SparkRound> _rounds;
  Timer? _heartbeat;
  Timer? _ticker;
  SparkSession? _session;
  bool _summaryShown = false;

  // Selección local pendiente (antes de enviar).
  String? _pendingChoice;
  String? _pendingGuess;

  String get _uid => widget.currentUid;

  @override
  void initState() {
    super.initState();
    _rounds =
        SparkRoundCatalog.buildRounds('${widget.matchId}:${widget.sessionId}');
    // Heartbeat de presencia cada 20s + uno inmediato.
    _beat();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _beat());
    // Ticker 1s para countdown/presencia.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _maybeExpireOrAbandon();
    });
  }

  void _beat() {
    final SparkSession? s = _session;
    if (s != null && s.status.isLive) {
      widget.service.heartbeat(s, _uid).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _maybeExpireOrAbandon() {
    final SparkSession? s = _session;
    if (s == null || !s.status.isLive) return;
    // Countdown agotado.
    if (s.status == SparkStatus.active && s.remainingSeconds() <= 0) {
      widget.service.expireIfHost(session: s, uid: _uid);
      return;
    }
    // El otro lleva mucho sin dar señal -> abandono (solo lo marca el host).
    if (s.status == SparkStatus.active) {
      final SparkParticipant? other = s.participants[s.otherUid(_uid)];
      final bool otherOffline =
          !(other?.onlineWithin(SparkService.presenceWindow) ?? false);
      if (otherOffline && s.isHostUid(_uid) && (s.startedAt != null)) {
        // Da un margen desde el inicio para que el otro aparezca.
        final bool grace = DateTime.now().difference(s.startedAt!) <
            const Duration(seconds: 20);
        if (!grace) widget.service.abandon(session: s, uid: s.otherUid(_uid));
      }
    }
  }

  Future<void> _exit() async {
    final SparkSession? s = _session;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('¿Salir de Spark?'),
        content: const Text(
            'Podéis seguir en el chat normal cuando queráis. Se cerrará la partida.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir jugando')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (confirm != true) return;
    if (s != null && s.status.isLive) {
      await widget.service.abandon(session: s, uid: _uid);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _report() async {
    if (widget.onReport != null) await widget.onReport!();
  }

  // --- Lógica de ronda ---

  SparkRound get _currentRound {
    final int i = (_session?.currentRound ?? 0).clamp(0, _rounds.length - 1);
    return _rounds[i];
  }

  Future<void> _submitChoice(SparkRound round) async {
    final SparkSession? s = _session;
    final String? choice = _pendingChoice;
    if (s == null || choice == null) return;

    Object value;
    if (round.kind == SparkRoundKind.guess) {
      if (_pendingGuess == null) return; // requiere elegir y adivinar
      value = <String, dynamic>{'choice': choice, 'guess': _pendingGuess};
    } else {
      value = choice;
    }
    if (round.kind == SparkRoundKind.react) {
      await widget.service.submitReaction(
          session: s, uid: _uid, roundId: round.id, reaction: choice);
    }
    await widget.service
        .submitAnswer(session: s, uid: _uid, roundId: round.id, value: value);
    setState(() {
      _pendingChoice = null;
      _pendingGuess = null;
    });
  }

  /// Cuando ambos han respondido, el host avanza tras un breve reveal.
  void _maybeAdvance(SparkSession s, SparkRound round) {
    if (!s.bothAnswered(round.id)) return;
    if (!s.isHostUid(_uid)) return; // solo el host orquesta
    // Pequeño reveal antes de avanzar.
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      final SparkSession? cur = _session;
      if (cur == null || cur.currentRound != s.currentRound) return;
      if (!cur.bothAnswered(round.id)) return;
      widget.service.advanceIfHost(
        session: cur,
        uid: _uid,
        rounds: _rounds,
        hostName: cur.isHostUid(_uid) ? 'Tú' : widget.otherName,
        guestName: cur.isHostUid(_uid) ? widget.otherName : 'Tú',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: AttraGradientBackground(
        child: SafeArea(
          child: StreamBuilder<SparkSession?>(
            stream:
                widget.service.watchSession(widget.matchId, widget.sessionId),
            builder: (BuildContext context, AsyncSnapshot<SparkSession?> snap) {
              final SparkSession? s = snap.data;
              _session = s;
              if (s == null) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.attraRed));
              }
              _maybeShowSummary(s);
              return Column(
                children: <Widget>[
                  _header(s),
                  Expanded(child: _body(s)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _maybeShowSummary(SparkSession s) {
    if (s.status == SparkStatus.completed && !_summaryShown) {
      _summaryShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSparkSummarySheet(
          context,
          summary: s.summary ?? <String, dynamic>{},
          onUseQuestion: widget.onUseQuestion,
          onOpenChat: () {
            Navigator.of(context).maybePop();
            widget.onOpenChat?.call();
          },
        );
      });
    }
  }

  // --- Secciones ---

  Widget _header(SparkSession s) {
    final int secs = s.status == SparkStatus.active ? s.remainingSeconds() : 0;
    final String mmss =
        '${(secs ~/ 60)}:${(secs % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: _exit,
            icon: Icon(Icons.close_rounded, color: context.colors.textPrimary),
            tooltip: 'Salir',
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text('Attra Spark',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                if (s.status == SparkStatus.active)
                  Text(
                    'Ronda ${s.currentRound + 1} de ${s.totalRounds}  ·  $mmss',
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _report,
            icon:
                Icon(Icons.flag_outlined, color: context.colors.textSecondary),
            tooltip: 'Reportar',
          ),
        ],
      ),
    );
  }

  Widget _body(SparkSession s) {
    switch (s.status) {
      case SparkStatus.waiting:
        return _waiting(s);
      case SparkStatus.active:
        return _activeRound(s);
      case SparkStatus.completed:
        return _ended(
            '¡Habéis completado Attra Spark!', Icons.celebration_rounded);
      case SparkStatus.abandoned:
        return _ended(
            s.abandonedBy == _uid
                ? 'Has salido de la partida.'
                : 'La otra persona salió. ¡Podéis seguir en el chat!',
            Icons.exit_to_app_rounded);
      case SparkStatus.expired:
        return _ended('Se acabó el tiempo. ¡Seguid en el chat!',
            Icons.hourglass_bottom_rounded);
    }
  }

  Widget _waiting(SparkSession s) {
    final bool iAccepted = s.participants[_uid]?.accepted ?? false;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.bolt_rounded, size: 56, color: AppColors.attraRed),
            const SizedBox(height: 16),
            Text(
              iAccepted
                  ? 'Esperando a que ${widget.otherName} acepte…'
                  : '${widget.otherName} te invita a jugar 5 minutos',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Romped el hielo con un juego rápido. Opcional.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary)),
            const SizedBox(height: 24),
            if (!iAccepted)
              AttraPrimaryButton(
                label: 'Aceptar y jugar',
                icon: Icons.play_arrow_rounded,
                onPressed: () => widget.service.accept(session: s, uid: _uid),
              )
            else
              const CircularProgressIndicator(color: AppColors.attraRed),
            const SizedBox(height: 12),
            AttraGhostButton(label: 'Ahora no', onPressed: _exit),
          ],
        ),
      ),
    );
  }

  Widget _activeRound(SparkSession s) {
    final SparkRound round = _currentRound;
    final bool iAnswered = s.hasAnswered(round.id, _uid);
    final bool otherAnswered = s.hasAnswered(round.id, s.otherUid(_uid));
    final bool both = s.bothAnswered(round.id);
    if (both) _maybeAdvance(s, round);

    // Presencia del otro.
    final bool otherOnline = s.participants[s.otherUid(_uid)]
            ?.onlineWithin(SparkService.presenceWindow) ??
        false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: <Widget>[
        if (!otherOnline) _pausedBanner(),
        const SizedBox(height: 8),
        Text(round.title.toUpperCase(),
            style: const TextStyle(
                color: AppColors.attraRed,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontSize: 12)),
        const SizedBox(height: 8),
        Text(round.prompt,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2)),
        const SizedBox(height: 20),
        if (both)
          _reveal(s, round)
        else if (iAnswered)
          _waitingOther(otherAnswered)
        else
          _answerControls(round),
      ],
    );
  }

  Widget _pausedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.colors.textMuted)),
          const SizedBox(width: 8),
          Text('Esperando a ${widget.otherName}…',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _answerControls(SparkRound round) {
    final bool isGuess = round.kind == SparkRoundKind.guess;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isGuess)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Tú eliges:',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
        ...round.options.map((SparkOption o) => _optionTile(
              o,
              selected: _pendingChoice == o.key,
              onTap: () => setState(() => _pendingChoice = o.key),
            )),
        if (isGuess) ...<Widget>[
          const SizedBox(height: 14),
          Text('¿Qué crees que elegirá?',
              style: TextStyle(color: context.colors.textSecondary)),
          const SizedBox(height: 6),
          ...round.options.map((SparkOption o) => _optionTile(
                o,
                selected: _pendingGuess == o.key,
                accent: AppColors.gold,
                onTap: () => setState(() => _pendingGuess = o.key),
              )),
        ],
        const SizedBox(height: 18),
        AttraPrimaryButton(
          label: 'Confirmar',
          icon: Icons.check_rounded,
          onPressed:
              (_pendingChoice != null && (!isGuess || _pendingGuess != null))
                  ? () => _submitChoice(round)
                  : null,
        ),
      ],
    );
  }

  Widget _waitingOther(bool otherAnswered) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              otherAnswered
                  ? 'Revelando…'
                  : '${widget.otherName} está respondiendo…',
              style: TextStyle(color: context.colors.textPrimary),
            ),
          ),
          if (!otherAnswered)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.attraRed)),
        ],
      ),
    );
  }

  Widget _reveal(SparkSession s, SparkRound round) {
    final String mine = _choiceKey(s.answerOf(round.id, _uid));
    final String theirs = _choiceKey(s.answerOf(round.id, s.otherUid(_uid)));
    final bool coincide = mine.isNotEmpty && mine == theirs;
    String label(String key) {
      for (final SparkOption o in round.options) {
        if (o.key == key) return '${o.emoji} ${o.label}'.trim();
      }
      return key;
    }

    // Para "guess": ¿acerté lo del otro?
    String? guessLine;
    if (round.kind == SparkRoundKind.guess) {
      final Object? myAns = s.answerOf(round.id, _uid);
      final String myGuess =
          (myAns is Map ? myAns['guess']?.toString() : '') ?? '';
      if (myGuess.isNotEmpty) {
        guessLine = myGuess == theirs
            ? '¡Acertaste lo que elegiría!'
            : 'No acertaste lo del otro, ¡pero bien jugado!';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: coincide
                  ? AppColors.match
                  : <Color>[context.colors.surfaceHigh, context.colors.surface],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            children: <Widget>[
              Text(
                coincide ? '¡Coincidís! ✨' : 'Os complementáis 😉',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget mineChip = _revealChip('Tú', label(mine));
                  final Widget theirChip =
                      _revealChip(widget.otherName, label(theirs));
                  if (constraints.maxWidth < 320) {
                    return Column(
                      children: <Widget>[
                        mineChip,
                        const SizedBox(height: 8),
                        theirChip,
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: mineChip),
                      const SizedBox(width: 10),
                      Expanded(child: theirChip),
                    ],
                  );
                },
              ),
              if (guessLine != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(guessLine,
                    style: TextStyle(color: context.colors.textPrimary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          s.isHostUid(_uid)
              ? 'Pasando a la siguiente…'
              : 'Esperando a la siguiente ronda…',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _revealChip(String who, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.bg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: <Widget>[
          Text(
            who,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.colors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _optionTile(SparkOption o,
      {required bool selected, required VoidCallback onTap, Color? accent}) {
    final Color color = accent ?? AppColors.attraRed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.18)
            : context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                  color: selected ? color : context.colors.surfaceLine,
                  width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: <Widget>[
                if (o.emoji.isNotEmpty) ...<Widget>[
                  Text(o.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(o.label,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ended(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: AppColors.attraRed),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            AttraPrimaryButton(
              label: 'Abrir chat',
              icon: Icons.chat_bubble_rounded,
              onPressed: () {
                Navigator.of(context).maybePop();
                widget.onOpenChat?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _choiceKey(Object? answer) {
    if (answer is String) return answer;
    if (answer is Map) {
      final Object? c = answer['choice'];
      if (c is String) return c;
    }
    return '';
  }
}
