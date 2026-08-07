import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/profile_summary.dart';
import '../data/live_local_media.dart';
import '../data/live_moderation_sampler.dart';
import '../data/live_rtc_config.dart';
import '../data/live_rtc_session.dart';
import '../data/live_service.dart';
import '../domain/live_block_notice.dart';
import '../domain/live_constants.dart';
import '../domain/live_rules.dart';
import '../domain/live_session.dart';
import '../domain/live_strikes.dart';

/// Fases de la pantalla del vivo, de principio a fin.
enum LivePhase {
  /// Nada en marcha (pantalla recién abierta o ya cerrada del todo).
  idle,

  /// Comprobando sanciones y pidiendo cámara/micro.
  preparing,

  /// Normas en pantalla, esperando aceptación. La cámara sigue APAGADA.
  rules,

  /// Sin cámara o sin micro: la pantalla explica por qué hacen falta.
  permissionDenied,

  /// Vetado del vivo por strikes.
  blocked,

  /// En la cola, buscando pareja.
  searching,

  /// Hay sesión y se está estableciendo el vídeo.
  connecting,

  /// Vídeo en curso.
  active,

  /// La sesión terminó y falta el veredicto.
  verdict,

  /// Todo cerrado: resumen (match / no match / sanción).
  ended,

  /// Fallo técnico del que se puede reintentar.
  error,
}

/// Orquestador del FEED EN VIVO en el cliente.
///
/// Junta cuatro cosas que van a ritmos distintos y tienen que acabar de
/// acuerdo: la cola de emparejamiento (backend), el documento de la sesión
/// (Firestore), la conexión WebRTC (peer a peer) y el muestreo de moderación.
/// Se hace en un único sitio a propósito: repartido por la UI sería imposible
/// garantizar que al cerrar la pantalla se apaga la cámara y se sale de la
/// cola pase lo que pase.
class LiveController extends ChangeNotifier {
  LiveController({
    required LiveService service,
    required String uid,
    ProfileSummaryRepository? profileSummaryRepository,
  })  : _service = service,
        _uid = uid,
        _profiles = profileSummaryRepository;

  final LiveService _service;
  final String _uid;
  final ProfileSummaryRepository? _profiles;

  String get uid => _uid;

  LivePhase _phase = LivePhase.idle;
  LivePhase get phase => _phase;

  LiveSession? _session;
  LiveSession? get session => _session;

  LiveRtcSession? _rtc;
  LiveRtcSession? get rtc => _rtc;

  LiveLocalPreview? _preview;

  /// Cámara propia encendida en la sala de espera (null en cuanto empieza la
  /// llamada: a partir de ahí el stream es de [rtc]).
  LiveLocalPreview? get preview => _preview;

  LiveStrikes _strikes = const LiveStrikes.clean('');
  LiveStrikes get strikes => _strikes;

  LiveBlockNotice? _block;

  /// Sanción vigente cuando [phase] es [LivePhase.blocked]. La UI la necesita
  /// para distinguir el bloqueo temporal (hay que esperar) del permanente (no
  /// hay nada que esperar) sin tener que interpretar el texto del mensaje.
  LiveBlockNotice? get blockNotice => _block;

  ProfileSummary? _peer;
  ProfileSummary? get peer => _peer;

  Duration _remaining = LiveConstants.sessionMax;

  /// Tiempo que queda de los 3 minutos. La UI pinta el contador con esto.
  Duration get remaining => _remaining;

  LiveVerdict? _myVerdict;
  LiveVerdict? get myVerdict => _myVerdict;

  LiveVerdictResult? _verdictResult;

  /// Resultado del cruce: si hay match, trae matchId/chatId.
  LiveVerdictResult? get verdictResult => _verdictResult;

  LiveEndReason? _endReason;
  LiveEndReason? get endReason => _endReason;

  String _message = '';

  /// Mensaje visible para el usuario (error, aviso de moderación, sanción).
  String get message => _message;

  /// Aviso de moderación recibido durante la llamada (1.er strike propio).
  String _moderationNotice = '';
  String get moderationNotice => _moderationNotice;

  bool _submittingVerdict = false;
  bool get submittingVerdict => _submittingVerdict;

  /// Sin TURN configurado hay conexiones que sencillamente no se establecen
  /// (NAT simétrico). La UI lo usa para explicar un fallo que si no parecería
  /// arbitrario.
  bool get turnConfigured => LiveIceConfig.hasTurn;

  String? get peerUid => _session?.otherUid(_uid);

  bool get isLive =>
      _phase == LivePhase.active || _phase == LivePhase.connecting;

  /// ¿Hay que impedir que la pantalla se apague?
  ///
  /// Incluye la sala de espera además de la llamada: ahí la cámara YA está
  /// encendida y seguimos en la cola, así que un apagado de pantalla nos
  /// emparejaría con alguien mientras el móvil duerme y le gastaría el turno.
  bool get keepsScreenAwake =>
      _phase == LivePhase.searching ||
      _phase == LivePhase.connecting ||
      _phase == LivePhase.active;

  StreamSubscription<LiveSession?>? _sessionSub;
  StreamSubscription<LiveStrikes>? _strikesSub;
  StreamSubscription<LiveVerdict?>? _verdictSub;
  Timer? _ticker;
  Timer? _queueRetry;
  Timer? _connectTimeout;
  LiveModerationSampler? _sampler;

  /// Margen para establecer el vídeo antes de rendirse.
  ///
  /// Sin tope, una conexión que nunca cuaja (el caso típico sin TURN) deja al
  /// usuario mirando una pantalla negra hasta que se aburre, y al otro
  /// esperando a alguien que nunca aparece. Mejor cortar y volver a buscar.
  static const Duration _connectDeadline = Duration(seconds: 30);

  bool _disposed = false;
  bool _closingSession = false;

  /// ¿Hemos llegado a pedir sitio en la cola?
  ///
  /// Con la pantalla de normas delante hay una salida —"ahora no"— que antes no
  /// existía: se abandona sin haber entrado nunca en la cola. Sin esta marca,
  /// cada cancelación gastaba una llamada a `leaveLiveQueue` para borrar algo
  /// que no existe. Se marca ANTES de llamar a `joinLiveQueue`, no después: si
  /// la llamada falla a medias podríamos haber quedado apuntados igualmente, y
  /// quedarse en la cola es mucho peor que una llamada de más.
  bool _joinedQueue = false;

  // --- Ciclo de vida público ---

  /// Primer paso al abrir la pantalla. NO enciende la cámara.
  ///
  /// Orden deliberado —sanción, luego normas, luego permisos— porque cada paso
  /// invalida al siguiente:
  /// - A quien está vetado no tiene sentido hacerle leer unas normas ni
  ///   pedirle la cámara para acabar diciéndole que no puede entrar.
  /// - Las normas van ANTES del diálogo de permisos del sistema: quien acepta
  ///   la cámara tiene que saber ya que lo que emita se analiza y qué pasa si
  ///   incumple. Enseñarlo después es justo lo que la guideline 1.2 considera
  ///   insuficiente.
  Future<void> prepareEntry() async {
    if (_disposed) return;
    if (_phase != LivePhase.idle &&
        _phase != LivePhase.ended &&
        _phase != LivePhase.error) {
      return;
    }
    _reset();
    _set(LivePhase.preparing, message: '');

    _strikes = await _service.fetchStrikes(_uid);
    if (_disposed) return;
    if (_applyBlockIfSanctioned(_strikes)) return;

    if (LiveRulesConsent.accepted) {
      await start();
      return;
    }
    _set(LivePhase.rules);
  }

  /// El usuario ha leído y aceptado las normas: a partir de aquí sí se pide la
  /// cámara. La aceptación vale para toda la ejecución de la app (ver
  /// [LiveRulesConsent]), no para siempre.
  Future<void> acceptRules() async {
    if (_disposed || _phase != LivePhase.rules) return;
    LiveRulesConsent.accept();
    _set(LivePhase.idle);
    await start();
  }

  /// Entra al vivo: comprueba sanciones, entra en la cola y espera pareja.
  ///
  /// Da por hecho que las normas ya están aceptadas: el camino público es
  /// [prepareEntry]. Se mantiene el chequeo de sanciones porque `searchAgain()`
  /// vuelve por aquí y entre llamada y llamada pueden haberte sancionado.
  Future<void> start() async {
    if (_disposed) return;
    if (_phase != LivePhase.idle &&
        _phase != LivePhase.ended &&
        _phase != LivePhase.error) {
      return;
    }
    _reset();
    _set(LivePhase.preparing, message: '');

    // Cortesía: si ya está sancionado, se lo decimos ANTES de encender la
    // cámara. La defensa real es del backend, que vuelve a mirarlo al
    // emparejar; esto solo evita un mensaje de error genérico.
    _strikes = await _service.fetchStrikes(_uid);
    if (_disposed) return;
    if (_applyBlockIfSanctioned(_strikes)) return;

    _strikesSub = _service.watchStrikes(_uid).listen(_onStrikes);

    // Cámara y micro ANTES de entrar en la cola. Si el permiso se pidiera al
    // emparejar, un "no" dejaría a la otra persona esperando un vídeo que
    // nunca llega y le habría gastado su turno.
    try {
      _preview = await LiveLocalPreview.open();
      if (_disposed) {
        await _preview?.dispose();
        _preview = null;
        return;
      }
    } on LiveMediaException catch (error) {
      _message = error.message;
      _set(error.permissionDenied
          ? LivePhase.permissionDenied
          : LivePhase.error);
      await _strikesSub?.cancel();
      _strikesSub = null;
      return;
    }

    try {
      _joinedQueue = true;
      final LiveQueueTicket ticket = await _service.joinQueue();
      if (_disposed) return;
      if (ticket.isBlocked) {
        _applyBlock(LiveBlockNotice(
          permanent: ticket.permanentlyBlocked,
          until: ticket.permanentlyBlocked ? null : ticket.blockedUntil,
        ));
        return;
      }
      if (ticket.isPaired) {
        // El backend ya nos tenía emparejados (reentrada tras perder la
        // pantalla): vamos directos a la sesión sin pasar por el sondeo.
        final LiveSession? existing =
            await _service.fetchSession(ticket.sessionId!);
        if (_disposed) return;
        if (existing != null && existing.isLive) {
          await _beginSession(existing);
          return;
        }
      }
      if (_phase == LivePhase.preparing) {
        _set(LivePhase.searching);
      }
      _scheduleMatchPolling();
    } on LiveServiceException catch (error) {
      if (error.isBlocked) {
        await _applyBackendBlock();
      } else {
        _failWith(error.message);
      }
    } catch (_) {
      _failWith('No hemos podido entrar en el directo. Inténtalo otra vez.');
    }
  }

  /// Sale del vivo por completo (botón atrás, cambio de pestaña, cierre).
  ///
  /// Es la operación más importante de esta clase: tiene que apagar la cámara
  /// y sacarnos de la cola SIEMPRE, aunque algo haya fallado antes. Dejar una
  /// entrada huérfana en `liveQueue` emparejaría a alguien con un móvil que ya
  /// no escucha.
  Future<void> leave() async {
    _queueRetry?.cancel();
    _queueRetry = null;
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _ticker?.cancel();
    _ticker = null;
    _sampler?.stop();
    _sampler = null;

    final LiveSession? current = _session;
    await _sessionSub?.cancel();
    _sessionSub = null;
    await _verdictSub?.cancel();
    _verdictSub = null;
    await _strikesSub?.cancel();
    _strikesSub = null;

    // Cortar la sesión antes de soltar el vídeo: el otro debe enterarse de que
    // nos hemos ido, no quedarse mirando una imagen congelada.
    if (current != null && current.isLive) {
      try {
        await _service.endSession(current.id, LiveEndReason.left);
      } catch (_) {/* la sesión pudo cerrarla ya el backend */}
    }
    await _disposeRtc();

    // La preview de la sala de espera también apaga la cámara: salir de aquí
    // no puede dejar el LED encendido bajo ningún camino.
    final LiveLocalPreview? preview = _preview;
    _preview = null;
    _notify();
    await preview?.dispose();

    if (_joinedQueue) {
      try {
        await _service.leaveQueue();
      } catch (_) {/* si falla, el backend caduca la entrada por `joinedAt` */}
    }
  }

  /// Cuelga: cierra la sesión y pasa a pedir veredicto.
  Future<void> hangUp() => _closeSession(LiveEndReason.left);

  /// La app se fue a segundo plano estando en vídeo.
  ///
  /// Se corta. Un vídeo 1:1 con un desconocido no puede seguir emitiendo
  /// nuestra cámara mientras la pantalla está apagada o en otra app.
  Future<void> handleAppBackgrounded() async {
    if (!isLive) return;
    await _closeSession(LiveEndReason.left);
  }

  /// ¿Se puede denunciar cerrando la sesión, o hay que ir por el flujo normal
  /// de reportes?
  ///
  /// `endLiveSession` solo crea el reporte MIENTRAS la sesión sigue viva: el
  /// backend aplica "el primer cierre gana" y el segundo es un no-op, así que
  /// llamarlo sobre una sesión ya cerrada se traga la denuncia en silencio.
  /// Quien reporte desde el veredicto o el resumen debe usar `reportUser`
  /// ([SafetyActions]), que escribe en la MISMA cola de moderación.
  bool get canReportThroughSession => _session?.isLive == true;

  /// Denuncia al otro y corta la sesión en un solo paso.
  ///
  /// Va por `endLiveSession(reason: 'reported')` en lugar de por `reportUser`
  /// porque el backend hace las tres cosas de golpe y de forma coherente:
  /// crea el reporte en la MISMA cola de moderación que `reportUser`, cierra
  /// la sesión para ambos y escribe dislike en los dos sentidos para que no
  /// se vuelvan a cruzar. Llamar a las dos crearía un reporte duplicado.
  ///
  /// Devuelve si la denuncia LLEGÓ al backend por este camino.
  ///
  /// `false` (sesión ya cerrada, o el cierre falló) significa que quien llama
  /// debe reenviarla por `reportUser`. Ante la duda se reenvía: un reporte
  /// duplicado lo descarta moderación en un vistazo, uno perdido no lo
  /// recupera nadie.
  Future<bool> reportPeer(String reason, {String details = ''}) async {
    final LiveSession? current = _session;
    if (current == null) return false;
    _moderationNotice = '';
    bool delivered = false;
    if (current.isLive) {
      try {
        await _service.endSession(
          current.id,
          LiveEndReason.reported,
          reportReason: reason,
          details: details,
        );
        delivered = true;
      } catch (_) {
        // Aunque falle el aviso al backend, cerramos en local: nadie tiene
        // que seguir viendo a quien acaba de denunciar.
      }
    }
    _endReason ??= LiveEndReason.reported;
    await _finishSession(LiveEndReason.reported);
    return delivered;
  }

  /// Se ha reportado o bloqueado a la otra persona DESPUÉS de que la sesión
  /// terminara (desde el veredicto o el resumen).
  ///
  /// Cierra el recorrido en el resumen: seguir pidiendo "¿te ha interesado?"
  /// sobre alguien a quien se acaba de denunciar sería absurdo, y con
  /// `endReason: reported` el resumen tampoco ofrece buscar a otra persona de
  /// inmediato.
  void handleReportedAfterSession() {
    if (_disposed) return;
    _moderationNotice = '';
    _endReason = LiveEndReason.reported;
    _set(LivePhase.ended);
  }

  /// Corta la sesión sin denunciar (p. ej. tras bloquear a la otra persona,
  /// que ya tiene su propio flujo en `SafetyActions`).
  Future<void> handleReported() async {
    _moderationNotice = '';
    await _closeSession(LiveEndReason.left);
  }

  /// Vuelve a buscar tras terminar una sesión.
  Future<void> searchAgain() async {
    await leave();
    _set(LivePhase.idle);
    await start();
  }

  // --- Veredicto ---

  /// Registra la decisión (derecha = like, izquierda = pass).
  ///
  /// Se puede dar DURANTE la llamada (deslizando) o al terminar. Es
  /// IRREVERSIBLE a propósito: permitir cambiarlo abriría la puerta a que un
  /// cliente sondease el veredicto del otro repitiendo la jugada.
  Future<void> decide(LiveVerdict verdict) async {
    final LiveSession? current = _session;
    if (current == null || _myVerdict != null || _submittingVerdict) return;
    _submittingVerdict = true;
    _notify();
    try {
      final LiveVerdictResult result =
          await _service.submitVerdict(current.id, verdict);
      _myVerdict = verdict;
      _verdictResult = result;
      // Si el cruce dio match, el backend cierra la sesión con
      // `endReason: matched` y ya lo veremos por el listener; no lo
      // adelantamos aquí para no pintar un match que el servidor no confirmó.
      if (_phase == LivePhase.verdict) {
        _set(LivePhase.ended);
      }
    } on LiveServiceException catch (error) {
      _message = error.message;
    } catch (_) {
      _message = 'No hemos podido registrar tu decisión.';
    } finally {
      _submittingVerdict = false;
      _notify();
    }
  }

  // --- Interna: cola y sesión ---

  /// Evita que la respuesta de `joinLiveQueue` y el sondeo arranquen la MISMA
  /// sesión a la vez: son dos caminos que pueden descubrir la pareja casi
  /// simultáneamente, y abrir dos veces la cámara y la conexión sería un
  /// desastre difícil de depurar.
  bool _startingSession = false;

  Future<void> _beginSession(LiveSession session) async {
    if (_startingSession || _session != null || _disposed) return;
    _startingSession = true;
    _queueRetry?.cancel();
    _queueRetry = null;

    _session = session;
    _endReason = null;
    _set(LivePhase.connecting);
    unawaited(_loadPeer(session.otherUid(_uid)));

    // A partir de aquí seguimos el documento CONCRETO de la sesión: es donde
    // aparecen el paso a `active`, el `endsAt` que fija el servidor y el
    // `endReason` con el que se cerró (incluido el corte por moderación).
    _sessionSub = _service.watchSession(session.id).listen(_onSessionChanged);
    // Veredicto propio: si se reabre la pantalla, no lo volvemos a pedir.
    _verdictSub = _service.watchVerdict(session.id, _uid).listen(
      (LiveVerdict? verdict) {
        if (verdict == null || _disposed) return;
        _myVerdict = verdict;
        _notify();
      },
    );

    // La cámara ya está abierta desde la sala de espera: se CEDE a la llamada
    // en vez de reabrirla (reabrir parpadea el LED y en algunos Android falla
    // con "cámara en uso" porque la anterior aún no se liberó).
    final LiveLocalPreview? preview = _preview;
    final MediaStream? handedStream = preview?.release();
    _preview = null;
    unawaited(preview?.dispose() ?? Future<void>.value());

    // `userA` (uid menor, mismo criterio que pairId) siempre oferta. Un rol
    // determinista evita el "glare" de dos ofertas simultáneas.
    final LiveRtcSession rtc = LiveRtcSession(
      service: _service,
      sessionId: session.id,
      selfUid: _uid,
      peerUid: session.otherUid(_uid),
      isCaller: _uid == session.userA,
      localStream: handedStream,
    );
    _rtc = rtc;
    rtc.onConnected = _onRtcConnected;
    rtc.onFailed = _onRtcFailed;
    _connectTimeout?.cancel();
    _connectTimeout = Timer(_connectDeadline, () {
      if (_disposed || _phase != LivePhase.connecting) return;
      _onRtcFailed();
    });
    _notify();

    try {
      await rtc.start();
    } on LiveMediaException catch (error) {
      _message = error.message;
      _set(error.permissionDenied ? LivePhase.permissionDenied : LivePhase.error);
      // Sin cámara no hay sesión posible: cerramos para no dejar al otro
      // esperando un vídeo que nunca llegará.
      await _closeSession(LiveEndReason.left, keepPhase: true);
    } catch (_) {
      _failWith('No hemos podido establecer la videollamada.');
      await _closeSession(LiveEndReason.left, keepPhase: true);
    } finally {
      _startingSession = false;
    }
  }

  void _onRtcConnected() {
    if (_disposed || _session == null) return;
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _set(LivePhase.active);
    // El servidor no puede saber cuándo conectó un enlace peer-to-peer, así
    // que se lo decimos nosotros. Él fija `startedAt`/`endsAt`: el tope de 3
    // minutos no puede depender del reloj del móvil.
    unawaited(
      _service.markActive(_session!.id).catchError((Object _) {}),
    );
    _startTicker();
    _startSampler();
  }

  void _onRtcFailed() {
    if (_disposed || !isLive) return;
    _message = turnConfigured
        ? 'Se ha perdido la conexión de vídeo.'
        : 'No se ha podido establecer la conexión de vídeo. Puede pasar en '
            'algunas redes móviles.';
    unawaited(_closeSession(LiveEndReason.left));
  }

  void _onSessionChanged(LiveSession? updated) {
    if (_disposed || updated == null) return;
    final LiveSession? current = _session;
    // Una sesión ya terminada NO puede revivir: la máquina de estados del
    // dominio lo prohíbe y aquí lo respetamos ignorando el snapshot.
    if (current != null && current.isEnded && updated.isLive) return;
    _session = updated;

    if (updated.isEnded) {
      // `??=`: si ya cerramos en local con un motivo más específico (timeout,
      // moderación), no lo pisamos con el genérico que escribe el backend.
      _endReason ??= updated.endReason;
      unawaited(_finishSession(updated.endReason ?? LiveEndReason.left));
      return;
    }
    _notify();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final LiveSession? current = _session;
      if (current == null) return;
      final Duration? left = current.remaining();
      _remaining = left ?? LiveConstants.sessionMax;
      // El backend también cierra por tiempo, pero el scheduler puede tardar y
      // tres minutos es un contrato con el usuario: en cuanto vence, cortamos
      // el vídeo LOCAL sin esperar a nadie.
      if (current.shouldAutoEnd()) {
        unawaited(_closeSession(LiveEndReason.timeout));
        return;
      }
      _notify();
    });
  }

  void _startSampler() {
    final LiveSession? current = _session;
    final LiveRtcSession? rtc = _rtc;
    if (current == null || rtc == null) return;
    _sampler?.stop();
    _sampler = LiveModerationSampler(
      service: _service,
      sessionId: current.id,
      // El objetivo es SIEMPRE el otro: se modera el vídeo que se recibe.
      targetUid: current.otherUid(_uid),
      remoteVideoTrack: () => rtc.remoteVideoTrack,
      onResult: _onModerationResult,
    )..start();
  }

  void _onModerationResult(LiveModerationResult result) {
    if (_disposed) return;
    if (!result.endSession) return;
    // El corte por moderación es INMEDIATO para ambos. No esperamos al
    // scheduler ni pedimos confirmación.
    _moderationNotice = 'Hemos cortado la sesión por contenido inapropiado.';
    unawaited(_closeSession(LiveEndReason.moderation));
  }

  void _onStrikes(LiveStrikes strikes) {
    if (_disposed) return;
    final int previous = _strikes.count;
    _strikes = strikes;
    final DateTime now = DateTime.now();
    if (strikes.count > previous && strikes.count > 0) {
      // Es NUESTRO contador: alguien ha denunciado nuestro vídeo desde el otro
      // lado. Lo decimos claro, incluida la consecuencia siguiente.
      final LiveStrikeDecision decision = strikes.decisionAt(now);
      _moderationNotice = _strikeMessage(decision, strikes);
      if (decision.endSession && isLive) {
        unawaited(_closeSession(LiveEndReason.moderation));
        return;
      }
    }
    if (!isLive && _applyBlockIfSanctioned(strikes)) return;
    _notify();
  }

  /// Cierra la sesión en el backend y libera el vídeo.
  ///
  /// [keepPhase] evita pisar una fase que ya explica algo más útil (por
  /// ejemplo "sin permiso de cámara").
  Future<void> _closeSession(
    LiveEndReason reason, {
    bool keepPhase = false,
  }) async {
    final LiveSession? current = _session;
    if (current == null || _closingSession) return;
    _closingSession = true;
    try {
      if (current.isLive) {
        try {
          await _service.endSession(current.id, reason);
        } catch (_) {
          // Si el backend no responde, seguimos cerrando en local: lo que no
          // puede pasar es que la cámara siga encendida.
        }
      }
    } finally {
      _closingSession = false;
    }
    await _finishSession(reason, keepPhase: keepPhase);
  }

  Future<void> _finishSession(
    LiveEndReason reason, {
    bool keepPhase = false,
  }) async {
    if (_disposed) return;
    _endReason ??= reason;
    _ticker?.cancel();
    _ticker = null;
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _sampler?.stop();
    _sampler = null;
    await _disposeRtc();
    if (_disposed) return;

    // Cerrar dos veces es normal (lo pide el cliente y además llega el
    // snapshot del backend). El PRIMER cierre manda: si ya estamos en la
    // pantalla de veredicto o en el resumen, no se recalcula la fase.
    if (_phase == LivePhase.verdict || _phase == LivePhase.ended) {
      _notify();
      return;
    }

    if (!keepPhase) {
      // Si aún no decidió, se le pide: el veredicto es lo que puede convertir
      // los 3 minutos en un match.
      _set(_myVerdict == null && !reason.isPunitive
          ? LivePhase.verdict
          : LivePhase.ended);
    } else {
      _notify();
    }

    // Ya no estamos en cola; salir es idempotente y barato.
    if (_joinedQueue) {
      try {
        await _service.leaveQueue();
      } catch (_) {/* sin consecuencias: la entrada caduca sola */}
    }
  }

  Future<void> _disposeRtc() async {
    final LiveRtcSession? rtc = _rtc;
    if (rtc == null) return;
    // Se quita de la vista ANTES de liberar: `RTCVideoView` pinta una textura
    // nativa y destruirla mientras un frame la usa peta en Android.
    _rtc = null;
    _notify();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await rtc.dispose();
  }

  /// Sondeo del emparejamiento.
  ///
  /// Entrar en la cola solo APUNTA: quien cruza candidatos y crea la sesión es
  /// `findLiveMatch`, así que hay que preguntar. El sondeo hace además de
  /// señal de vida —el backend descarta como zombis las entradas que llevan
  /// rato sin sondear— y de red de seguridad si se pierde el listener de
  /// Firestore.
  ///
  /// Cada 3 s: lo bastante rápido para que la espera no se note y lo bastante
  /// espaciado para no provocar contención en la transacción de emparejamiento
  /// del otro usuario.
  void _scheduleMatchPolling() {
    _queueRetry?.cancel();
    _pollMatchOnce();
    _queueRetry = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollMatchOnce(),
    );
  }

  bool _polling = false;

  void _pollMatchOnce() {
    if (_disposed || _polling || _phase != LivePhase.searching) return;
    _polling = true;
    unawaited(
      _service.findMatch().then<void>((LiveMatchPoll poll) async {
        if (_disposed || _session != null) return;
        if (!poll.paired || poll.sessionId == null) return;
        final LiveSession? session = await _service.fetchSession(
          poll.sessionId!,
        );
        if (_disposed || _session != null) return;
        if (session != null && session.isLive) {
          await _beginSession(session);
        }
      }).catchError((Object error) {
        // Un sondeo fallido NO saca al usuario de la pantalla: puede ser un
        // corte de red pasajero. Salvo que el backend diga que está vetado.
        if (error is LiveServiceException && error.isBlocked) {
          unawaited(_applyBackendBlock());
        }
      }).whenComplete(() => _polling = false),
    );
  }

  Future<void> _loadPeer(String uid) async {
    final ProfileSummaryRepository? repo = _profiles;
    if (repo == null || uid.isEmpty) return;
    try {
      final ProfileSummary summary = await repo.fetch(uid);
      if (_disposed) return;
      _peer = summary;
      _notify();
    } catch (_) {
      // El nombre es decorativo: sin él la llamada funciona igual.
    }
  }

  // --- Sanciones que impiden entrar ---

  /// Pinta la pantalla de veto si [strikes] veta AHORA. Devuelve si lo hizo,
  /// para que quien llama sepa que debe abandonar su flujo.
  bool _applyBlockIfSanctioned(LiveStrikes strikes) {
    final LiveBlockNotice? notice =
        LiveBlockNotice.fromStrikes(strikes, DateTime.now());
    if (notice == null) return false;
    _applyBlock(notice);
    return true;
  }

  void _applyBlock(LiveBlockNotice notice) {
    _block = notice;
    _set(LivePhase.blocked, message: _blockText(notice));
  }

  /// El backend nos ha cerrado la puerta (`permission-denied` de
  /// `assertLiveNotBlocked`).
  ///
  /// PORQUÉ releemos las sanciones en vez de mostrar `error.message`: el texto
  /// de la excepción es de servidor —pensado para logs, y a veces en inglés— y
  /// no distingue 24 h de para siempre. Leyendo `liveStrikes/{uid}` podemos
  /// contarlo con nuestras palabras. Si el documento no se deja leer, seguimos
  /// bloqueando (el backend manda) pero en neutro, sin inventarnos un plazo.
  Future<void> _applyBackendBlock() async {
    if (_disposed) return;
    final LiveStrikes strikes = await _service.fetchStrikes(_uid);
    if (_disposed) return;
    _strikes = strikes;
    if (_applyBlockIfSanctioned(strikes)) return;
    _applyBlock(LiveBlockNotice.unknown);
  }

  // --- Mensajes ---

  static const String _permanentBlockText =
      'Has perdido el acceso al directo por incumplir las normas de forma '
      'reiterada. Puedes seguir usando el resto de la app.';

  String _temporaryBlockText(DateTime? until) {
    if (until == null) {
      return 'El directo está bloqueado temporalmente para tu cuenta.';
    }
    final Duration left = until.difference(DateTime.now());
    final int hours = left.inHours;
    if (hours >= 1) {
      return 'El directo está bloqueado $hours h por contenido inapropiado.';
    }
    final int minutes = left.inMinutes.clamp(1, 59);
    return 'El directo está bloqueado $minutes min por contenido inapropiado.';
  }

  String _blockText(LiveBlockNotice notice) {
    if (notice.permanent) return _permanentBlockText;
    return _temporaryBlockText(notice.until);
  }

  String _strikeMessage(LiveStrikeDecision decision, LiveStrikes strikes) {
    switch (decision.action) {
      case LiveStrikeAction.warnAndEnd:
        return 'Hemos detectado contenido inapropiado en tu cámara y hemos '
            'cortado la sesión. A la próxima perderás el directo 24 horas.';
      case LiveStrikeAction.temporaryBlock:
        return _temporaryBlockText(strikes.blockedUntil);
      case LiveStrikeAction.permanentBlock:
        return _permanentBlockText;
      case LiveStrikeAction.none:
        return '';
    }
  }

  // --- Utilidades ---

  void _reset() {
    _session = null;
    _block = null;
    _joinedQueue = false;
    _startingSession = false;
    _polling = false;
    _closingSession = false;
    _peer = null;
    _myVerdict = null;
    _verdictResult = null;
    _endReason = null;
    _moderationNotice = '';
    _remaining = LiveConstants.sessionMax;
  }

  void _failWith(String message) {
    _message = message;
    _set(LivePhase.error);
  }

  void _set(LivePhase phase, {String? message}) {
    _phase = phase;
    if (message != null) _message = message;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    // `leave()` es asíncrono y este `dispose` no puede esperarlo, pero sí
    // tiene que dispararlo: la cámara no puede quedarse encendida porque el
    // widget se haya destruido.
    unawaited(leave());
    _disposed = true;
    super.dispose();
  }
}
