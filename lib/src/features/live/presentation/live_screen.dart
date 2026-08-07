import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../../../widgets/attra_image.dart';
import '../../match/data/match_service.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../safety/domain/report.dart';
import '../../safety/presentation/safety_actions.dart';
import '../data/live_local_media.dart';
import '../data/live_rtc_session.dart';
import '../data/live_service.dart';
import '../domain/live_block_notice.dart';
import '../domain/live_session.dart';
import 'live_controller.dart';
import 'live_rules_view.dart';
import 'live_verdict_swipe.dart';
import 'live_wakelock.dart';

/// Pantalla del FEED EN VIVO: sala de espera + videollamada 1:1 + veredicto.
///
/// Se monta con todo lo que necesita inyectado (nada de singletons) para que
/// la pestaña de Inicio pueda cablearla sin arrastrar dependencias raras.
class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.liveService,
    required this.matchService,
    required this.uid,
    this.profileSummaryRepository,
    this.onOpenChat,
  });

  final LiveService liveService;

  /// Para REPORTAR y BLOQUEAR: exactamente el mismo flujo que el feed y el
  /// chat (`SafetyActions`). No duplicamos el sistema de reportes.
  final MatchService matchService;

  final String uid;
  final ProfileSummaryRepository? profileSummaryRepository;

  /// Al hacer match desde el vivo se puede saltar al chat recién creado.
  final void Function(String chatId, String peerUid)? onOpenChat;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  late final LiveController _controller = LiveController(
    service: widget.liveService,
    uid: widget.uid,
    profileSummaryRepository: widget.profileSummaryRepository,
  );

  /// Impide que el sistema apague la pantalla mientras hay directo. Sin esto la
  /// llamada se cortaba sola: pantalla apagada → app en `paused` →
  /// `handleAppBackgrounded()` cierra la sesión.
  final LiveWakelock _wakelock = LiveWakelock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
    // NO arranca la cámara: `prepareEntry` comprueba primero si estás
    // sancionado y después enseña las normas. La cámara solo se enciende tras
    // aceptarlas (ver LiveController.prepareEntry).
    unawaited(_controller.prepareEntry());
  }

  void _onChanged() {
    if (!mounted) return;
    unawaited(_wakelock.update(keepAwake: _controller.keepsScreenAwake));
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Un vídeo 1:1 con un desconocido NO puede seguir emitiendo con la app en
    // segundo plano o la pantalla apagada.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.handleAppBackgrounded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    // Suelta el bloqueo pase lo que pase: salir del directo con la pantalla
    // clavada encendida se comería la batería sin explicación.
    unawaited(_wakelock.release());
    super.dispose();
  }

  /// Reportar / Bloquear a la otra persona. Disponible DURANTE la llamada y
  /// también después, en el veredicto y en el resumen.
  ///
  /// PORQUÉ los dos momentos: el caso que hay que cubrir es justo el peor —
  /// alguien te enseña algo y cuelga—. Si la denuncia dependiera de que la
  /// sesión siga viva, ese caso se quedaría sin denunciar.
  ///
  /// Y por eso hay DOS caminos de reporte, no uno:
  /// - Sesión viva: `endLiveSession(reason: 'reported')`, porque el backend
  ///   crea el reporte en la MISMA cola que `reportUser` Y ADEMÁS cierra la
  ///   sesión y escribe los dislikes de golpe. Llamar también a `reportUser`
  ///   duplicaría el reporte.
  /// - Sesión ya cerrada: `SafetyActions.report` (→ `reportUser`). El cierre
  ///   del backend es "el primero gana", así que reutilizar `endLiveSession`
  ///   aquí se habría tragado la denuncia sin decir nada.
  ///
  /// La lista de motivos es la compartida ([ReportReason]), no una copia.
  Future<void> _report() async {
    final String? peerUid = _controller.peerUid;
    if (peerUid == null || peerUid.isEmpty) return;
    final String name = _controller.peer?.displayName ?? 'esta persona';
    final bool live = _controller.canReportThroughSession;

    final _LiveSafetyChoice? choice =
        await showModalBottomSheet<_LiveSafetyChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('live-safety-report'),
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Reportar'),
              subtitle: Text(live
                  ? 'Cortamos la sesión y lo revisa nuestro equipo'
                  : 'Lo revisa nuestro equipo aunque la sesión ya haya '
                      'terminado'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LiveSafetyChoice.report),
            ),
            ListTile(
              key: const ValueKey<String>('live-safety-block'),
              leading: const Icon(Icons.block),
              title: const Text('Bloquear'),
              subtitle: Text('$name no podrá verte ni escribirte'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_LiveSafetyChoice.block),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _LiveSafetyChoice.block) {
      final SafetyActionResult result = await SafetyActions.block(
        context,
        matchService: widget.matchService,
        uid: peerUid,
        displayName: name,
      );
      if (result != SafetyActionResult.blocked) return;
      if (_controller.canReportThroughSession) {
        await _controller.handleReported();
      } else {
        // Ya no hay sesión que cerrar, pero tampoco tiene sentido seguir
        // preguntando "¿te ha interesado?" por alguien recién bloqueado.
        _controller.handleReportedAfterSession();
      }
      return;
    }

    final ReportReason? reason = await showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '¿Qué ocurre con $name?',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final ReportReason r in ReportReason.values)
              ListTile(
                title: Text(r.label),
                onTap: () => Navigator.of(sheetContext).pop(r),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    // El camino se decide AQUÍ y no al abrir la hoja: el tope de 3 minutos
    // sigue corriendo mientras se elige el motivo, así que la sesión puede
    // haber vencido por el camino. `reportPeer` devuelve si la denuncia llegó
    // de verdad; si no, se reenvía por `reportUser`.
    if (_controller.canReportThroughSession &&
        await _controller.reportPeer(reason.wireName)) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content:
              Text('Gracias. Nuestro equipo lo revisa en menos de 24 horas.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _sendReportAfterSession(peerUid, reason);
  }

  /// Denuncia con la sesión ya cerrada: va por `reportUser`, la MISMA cola de
  /// moderación que usa el resto de la app.
  ///
  /// No se reutiliza `SafetyActions.report` porque volvería a preguntar el
  /// motivo, que aquí ya está elegido; sí se copia su contrato de cara al
  /// usuario (mismo texto de confirmación y mismo aviso de fallo).
  Future<void> _sendReportAfterSession(String peerUid, ReportReason reason) async {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    try {
      await widget.matchService.reportUser(
        reportedUid: peerUid,
        reason: reason.wireName,
      );
      messenger?.showSnackBar(
        const SnackBar(
          content:
              Text('Gracias. Nuestro equipo lo revisa en menos de 24 horas.'),
        ),
      );
      _controller.handleReportedAfterSession();
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo enviar el reporte. Inténtalo otra vez.'),
        ),
      );
    }
  }

  Future<void> _openAppSettings() async {
    // iOS expone un esquema para abrir la ficha de la app; Android no tiene
    // equivalente accesible sin un plugin específico, así que allí explicamos
    // la ruta en texto (ver _PermissionView).
    if (kIsWeb || !Platform.isIOS) return;
    final Uri uri = Uri.parse('app-settings:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Salir de la pantalla debe apagar la cámara y sacarnos de la cola.
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) unawaited(_controller.leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_controller.phase) {
      case LivePhase.idle:
      case LivePhase.preparing:
        return const _WaitingView(title: 'Preparando el directo…');
      case LivePhase.rules:
        return LiveRulesView(
          onAccept: () => unawaited(_controller.acceptRules()),
          onCancel: () => Navigator.of(context).maybePop(),
        );
      case LivePhase.searching:
        return _WaitingView(
          title: 'Buscando a alguien…',
          subtitle: 'Vídeo de 3 minutos con una persona real. '
              'Desliza a la derecha si te interesa, a la izquierda si no.',
          preview: _controller.preview,
          onCancel: () async {
            await _controller.leave();
            if (mounted) Navigator.of(context).maybePop();
          },
        );
      case LivePhase.connecting:
      case LivePhase.active:
        return _CallView(
          controller: _controller,
          onReport: _report,
          onHangUp: () => unawaited(_controller.hangUp()),
        );
      case LivePhase.verdict:
        return _VerdictView(controller: _controller, onReport: _report);
      case LivePhase.ended:
        return _EndedView(
          controller: _controller,
          onSearchAgain: () => unawaited(_controller.searchAgain()),
          onClose: () => Navigator.of(context).maybePop(),
          onReport: _report,
          onOpenChat: widget.onOpenChat,
        );
      case LivePhase.permissionDenied:
        return _PermissionView(
          message: _controller.message,
          onRetry: () => unawaited(_controller.searchAgain()),
          onOpenSettings: _openAppSettings,
        );
      case LivePhase.blocked:
        return _BlockedView(
          notice: _controller.blockNotice ?? LiveBlockNotice.unknown,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case LivePhase.error:
        return _NoticeView(
          icon: Icons.wifi_off_rounded,
          title: 'No hemos podido conectar',
          message: _controller.message,
          actionLabel: 'Reintentar',
          onAction: () => unawaited(_controller.searchAgain()),
          onClose: () => Navigator.of(context).maybePop(),
        );
    }
  }
}

/// Opciones de la hoja de seguridad del vivo.
enum _LiveSafetyChoice { report, block }

// --- Sala de espera ---

class _WaitingView extends StatelessWidget {
  const _WaitingView({
    required this.title,
    this.subtitle,
    this.preview,
    this.onCancel,
  });

  final String title;
  final String? subtitle;

  /// Cámara propia ya encendida: verse mientras se espera es lo que uno
  /// espera de una videollamada y hace evidente que la cámara está activa.
  final LiveLocalPreview? preview;

  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final LiveLocalPreview? preview = this.preview;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (preview != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: SizedBox(
                width: 132,
                height: 190,
                child: RTCVideoView(
                  preview.renderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  placeholderBuilder: (BuildContext context) =>
                      const ColoredBox(color: Colors.white10),
                ),
              ),
            )
          else
            const _PulsingDot(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          // Aviso honesto: la cámara YA está encendida (se ve arriba) pero no
          // se está emitiendo a nadie todavía. Decirlo evita la sospecha
          // razonable de "¿me está viendo alguien ya?".
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                preview == null
                    ? Icons.videocam_off_outlined
                    : Icons.lock_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  preview == null
                      ? 'Tu cámara se activa al encontrar pareja'
                      : 'Nadie te ve todavía: solo tú',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (onCancel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxl),
            AttraSecondaryButton(
              label: 'Cancelar',
              onPressed: () => unawaited(onCancel!()),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: 72 + _c.value * 16,
          height: 72 + _c.value * 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06 + _c.value * 0.06),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          child: const Icon(Icons.sensors, color: Colors.white, size: 30),
        );
      },
    );
  }
}

// --- Videollamada ---

class _CallView extends StatelessWidget {
  const _CallView({
    required this.controller,
    required this.onReport,
    required this.onHangUp,
  });

  final LiveController controller;
  final Future<void> Function() onReport;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    final LiveRtcSession? rtc = controller.rtc;
    final bool connected = controller.phase == LivePhase.active;
    final bool decided = controller.myVerdict != null;

    final Widget remote = rtc == null
        ? const ColoredBox(color: Colors.black)
        : RTCVideoView(
            rtc.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            placeholderBuilder: (BuildContext context) =>
                const _ConnectingPlaceholder(),
          );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // El gesto envuelve el vídeo REMOTO: se decide sobre la persona que se
        // está viendo, igual que en el feed se decide sobre la tarjeta.
        LiveVerdictSwipe(
          enabled: connected && !decided && !controller.submittingVerdict,
          // La conversación continúa tras decidir: el vídeo vuelve a su sitio.
          returnToCenter: true,
          onVerdict: (LiveVerdict verdict) =>
              unawaited(controller.decide(verdict)),
          child: remote,
        ),

        // Degradados para que los controles se lean sobre cualquier imagen.
        const _ScrimTop(),
        const _ScrimBottom(),

        // Cabecera: contador + REPORTAR (siempre visible, Guideline 1.2).
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.lg,
          right: AppSpacing.sm,
          child: Row(
            children: <Widget>[
              _CountdownPill(remaining: controller.remaining),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  controller.peer?.displayName ?? 'Alguien',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Botón de denuncia SIEMPRE presente durante la llamada: es la
              // salida de emergencia y no puede estar escondida en un menú
              // secundario.
              _ReportTextButton(onPressed: onReport),
            ],
          ),
        ),

        // Vídeo propio, pequeño y arriba a la derecha.
        if (rtc != null)
          Positioned(
            top: 72,
            right: AppSpacing.lg,
            child: _SelfPreview(rtc: rtc),
          ),

        if (controller.moderationNotice.isNotEmpty)
          Positioned(
            top: 72,
            left: AppSpacing.lg,
            right: 140,
            child: _ModerationBanner(text: controller.moderationNotice),
          ),

        // Pie: controles + estado de la decisión.
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.xl,
          child: Column(
            children: <Widget>[
              if (decided)
                _DecisionChip(verdict: controller.myVerdict!)
              else if (connected)
                Text(
                  'Desliza →  si te interesa   ·   ←  si no',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              if (connected && !decided)
                LiveVerdictButtons(
                  enabled: !controller.submittingVerdict,
                  onVerdict: (LiveVerdict verdict) =>
                      unawaited(controller.decide(verdict)),
                ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (rtc != null) ...<Widget>[
                    ValueListenableBuilder<bool>(
                      valueListenable: rtc.micEnabled,
                      builder: (BuildContext context, bool on, Widget? _) =>
                          _CircleButton(
                        icon: on ? Icons.mic : Icons.mic_off,
                        tooltip: on ? 'Silenciar' : 'Activar micrófono',
                        onPressed: rtc.toggleMic,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _CircleButton(
                      icon: Icons.cameraswitch_outlined,
                      tooltip: 'Cambiar cámara',
                      onPressed: () => unawaited(rtc.switchCamera()),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                  ],
                  _CircleButton(
                    key: const ValueKey<String>('live-hangup'),
                    icon: Icons.call_end_rounded,
                    tooltip: 'Cortar',
                    danger: true,
                    onPressed: onHangUp,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectingPlaceholder extends StatelessWidget {
  const _ConnectingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              'Conectando…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.rtc});

  final LiveRtcSession rtc;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: SizedBox(
        width: 108,
        height: 156,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RTCVideoView(
              rtc.localRenderer,
              // Espejo: la gente espera verse como en un espejo, no invertida.
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              placeholderBuilder: (BuildContext context) =>
                  const ColoredBox(color: Colors.black26),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: ValueListenableBuilder<bool>(
                valueListenable: rtc.cameraEnabled,
                builder: (BuildContext context, bool on, Widget? _) => InkWell(
                  onTap: rtc.toggleCamera,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      on ? Icons.videocam : Icons.videocam_off,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final int total = remaining.inSeconds.clamp(0, 24 * 3600);
    final String label =
        '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    // Bajo 30 s el contador se destaca: el corte es duro y sin aviso sería
    // una sorpresa desagradable en mitad de una frase.
    final bool urgent = total <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: urgent
            ? Colors.redAccent.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.timer_outlined, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionChip extends StatelessWidget {
  const _DecisionChip({required this.verdict});

  final LiveVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final bool like = verdict.isLike;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            like ? Icons.favorite_rounded : Icons.check_rounded,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            like
                ? 'Le dirás que te interesa al terminar'
                : 'Decisión registrada',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ModerationBanner extends StatelessWidget {
  const _ModerationBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
      ),
    );
  }
}

class _ScrimTop extends StatelessWidget {
  const _ScrimTop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.65),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrimBottom extends StatelessWidget {
  const _ScrimBottom();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.75),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de denuncia. Uno solo para las tres pantallas donde aparece
/// (llamada, veredicto y resumen) para que se vea y se lea igual en las tres:
/// si el botón de emergencia cambia de sitio y de forma según la fase, deja de
/// reconocerse justo cuando hace falta.
class _ReportTextButton extends StatelessWidget {
  const _ReportTextButton({required this.onPressed, this.label = 'Reportar'});

  final Future<void> Function() onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey<String>('live-report'),
      onPressed: () => unawaited(onPressed()),
      icon: const Icon(Icons.flag_outlined, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: danger
              ? Colors.redAccent
              : Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Veredicto tras la llamada ---

class _VerdictView extends StatelessWidget {
  const _VerdictView({required this.controller, required this.onReport});

  final LiveController controller;
  final Future<void> Function() onReport;

  @override
  Widget build(BuildContext context) {
    final String name = controller.peer?.displayName ?? 'esa persona';
    final String photo = controller.peer?.photoUrl ?? '';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: <Widget>[
          // La denuncia sigue accesible aquí: el momento típico para querer
          // denunciar es justo cuando la llamada acaba de terminar, y hasta
          // ahora esta pantalla solo dejaba decir "me interesa" o "paso".
          Align(
            alignment: Alignment.centerRight,
            child: _ReportTextButton(onPressed: onReport),
          ),
          Text(
            '¿Te ha interesado $name?',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Solo se lo diremos si a la otra persona también.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: LiveVerdictSwipe(
              enabled: !controller.submittingVerdict,
              onVerdict: (LiveVerdict verdict) =>
                  unawaited(controller.decide(verdict)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                child: photo.isEmpty
                    ? Container(
                        color: Colors.white10,
                        alignment: Alignment.center,
                        child: const Icon(Icons.person,
                            size: 64, color: Colors.white24),
                      )
                    : AttraImage(url: photo, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          LiveVerdictButtons(
            enabled: !controller.submittingVerdict,
            onVerdict: (LiveVerdict verdict) =>
                unawaited(controller.decide(verdict)),
          ),
          if (controller.message.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              controller.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Resumen final ---

class _EndedView extends StatelessWidget {
  const _EndedView({
    required this.controller,
    required this.onSearchAgain,
    required this.onClose,
    required this.onReport,
    this.onOpenChat,
  });

  final LiveController controller;
  final VoidCallback onSearchAgain;
  final VoidCallback onClose;
  final Future<void> Function() onReport;
  final void Function(String chatId, String peerUid)? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final LiveVerdictResult? result = controller.verdictResult;
    final bool matched = result?.matched == true ||
        controller.endReason == LiveEndReason.matched;
    final bool punitive = controller.endReason?.isPunitive == true;
    final String? chatId = result?.chatId;
    final String? peerUid = controller.peerUid;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            matched
                ? Icons.favorite_rounded
                : punitive
                    ? Icons.gpp_maybe_outlined
                    : Icons.waving_hand_outlined,
            size: 56,
            color: Colors.white,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            matched
                ? '¡Match!'
                : punitive
                    ? 'Sesión cerrada'
                    : 'Se acabó el tiempo',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _summary(matched, punitive),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
          if (controller.moderationNotice.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              controller.moderationNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          if (matched && chatId != null && peerUid != null)
            AttraPrimaryButton(
              label: 'Abrir chat',
              onPressed: onOpenChat == null
                  ? null
                  : () => onOpenChat!(chatId, peerUid),
            ),
          if (matched && chatId != null) const SizedBox(height: AppSpacing.md),
          // Tras una sanción NO se ofrece volver a buscar de inmediato: sería
          // invitar a repetir justo lo que se acaba de cortar.
          if (!punitive)
            AttraSecondaryButton(
              label: 'Buscar a otra persona',
              onPressed: onSearchAgain,
            ),
          const SizedBox(height: AppSpacing.md),
          AttraGhostButton(label: 'Salir', onPressed: onClose),
          // Denunciar DESPUÉS de colgar. Es el caso que más importa cubrir:
          // quien enseña algo y corta la llamada contaba justamente con que
          // ya no se le pudiera denunciar. `endReason: reported` significa que
          // ya se hizo, así que ahí no se vuelve a ofrecer.
          if (peerUid != null &&
              peerUid.isNotEmpty &&
              controller.endReason != LiveEndReason.reported) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _ReportTextButton(
              onPressed: onReport,
              label: 'Reportar a esta persona',
            ),
          ],
        ],
      ),
    );
  }

  String _summary(bool matched, bool punitive) {
    if (matched) {
      return 'Os habéis gustado. Ya podéis hablar cuando queráis.';
    }
    if (punitive) {
      return 'Hemos cortado la sesión por seguridad. Gracias por avisar.';
    }
    if (controller.myVerdict == null) {
      return 'No hubo decisión, así que no pasa nada más.';
    }
    return controller.myVerdict!.isLike
        ? 'Si a la otra persona también le interesas, te avisamos.'
        : 'Sin match. Puedes seguir buscando.';
  }
}

// --- Permisos ---

class _PermissionView extends StatelessWidget {
  const _PermissionView({
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final bool isIos = !kIsWeb && Platform.isIOS;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.videocam_off_outlined,
              size: 56, color: Colors.white),
          const SizedBox(height: AppSpacing.xl),
          const Text(
            'Necesitamos tu cámara y tu micrófono',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // El PORQUÉ, no solo el qué: el directo es una conversación de vídeo
          // en tiempo real; sin cámara ni micro no hay nada que enseñar ni que
          // oír. El vídeo va cifrado punto a punto y no se graba.
          Text(
            'El directo es una videollamada de 3 minutos con otra persona. '
            'El vídeo va directo entre los dos móviles: no lo grabamos ni lo '
            'guardamos en ningún servidor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (isIos)
            AttraPrimaryButton(
              label: 'Abrir Ajustes',
              onPressed: () => unawaited(onOpenSettings()),
            )
          else
            Text(
              'Actívalos en Ajustes del sistema → Aplicaciones → Attra → '
              'Permisos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          const SizedBox(height: AppSpacing.md),
          AttraSecondaryButton(label: 'Reintentar', onPressed: onRetry),
        ],
      ),
    );
  }
}

// --- Sanción: no puedes entrar al directo ---

/// Explica el veto CON NUESTRAS PALABRAS.
///
/// PORQUÉ una pantalla propia y no el aviso genérico: el backend rechaza a los
/// sancionados con un `permission-denied` y antes se pintaba ese texto tal
/// cual, que ni distingue las 24 h de para siempre ni dice qué se puede hacer.
/// Son dos situaciones distintas: en una hay que esperar (y conviene saber
/// cuánto, y que a la siguiente ya no hay vuelta atrás) y en la otra no hay
/// nada que esperar, así que ofrecer "reintentar" sería mentir.
class _BlockedView extends StatelessWidget {
  const _BlockedView({required this.notice, required this.onClose});

  final LiveBlockNotice notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            notice.permanent ? Icons.block : Icons.hourglass_bottom_rounded,
            size: 56,
            color: Colors.white,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _body(now),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // El resto de la app sigue funcionando: decirlo evita que la sanción
          // del directo se lea como "me han echado de Attra".
          Text(
            'El resto de Attra funciona con normalidad: feed, chats y matches '
            'siguen ahí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AttraPrimaryButton(label: 'Entendido', onPressed: onClose),
        ],
      ),
    );
  }

  String get _title {
    if (notice.permanent) return 'Ya no puedes entrar al directo';
    if (notice.durationUnknown) return 'Directo no disponible';
    return 'Directo bloqueado temporalmente';
  }

  String _body(DateTime now) {
    if (notice.permanent) {
      return 'Has incumplido las normas del directo varias veces, así que has '
          'perdido el acceso de forma permanente. No se levanta con el tiempo: '
          'la decisión la revisa nuestro equipo de moderación.';
    }
    if (notice.durationUnknown) {
      return 'Ahora mismo no puedes entrar al directo por una sanción de '
          'moderación. Vuelve a intentarlo más tarde.';
    }
    return 'Se ha detectado contenido inapropiado en tu cámara. Podrás volver '
        'a entrar ${_remainingText(now)}, sin hacer nada: el bloqueo se '
        'levanta solo. Si vuelve a pasar, la pérdida de acceso es permanente.';
  }

  /// Redondea a favor del usuario (arriba) para no prometer un "en 1 h" que en
  /// realidad son 1 h 59 min.
  String _remainingText(DateTime now) {
    final Duration left = notice.remaining(now);
    if (left <= Duration.zero) return 'en unos minutos';
    if (left.inHours >= 1) {
      final int hours =
          left.inMinutes % 60 == 0 ? left.inHours : left.inHours + 1;
      return 'dentro de $hours h';
    }
    final int minutes = left.inMinutes < 1 ? 1 : left.inMinutes + 1;
    return 'dentro de $minutes min';
  }
}

// --- Avisos genéricos (error) ---

class _NoticeView extends StatelessWidget {
  const _NoticeView({
    required this.icon,
    required this.title,
    required this.message,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 56, color: Colors.white),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          if (actionLabel != null && onAction != null)
            AttraPrimaryButton(label: actionLabel!, onPressed: onAction),
          const SizedBox(height: AppSpacing.md),
          AttraGhostButton(label: 'Salir', onPressed: onClose),
        ],
      ),
    );
  }
}
