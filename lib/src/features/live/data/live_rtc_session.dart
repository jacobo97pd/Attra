import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'live_local_media.dart';
import 'live_rtc_config.dart';
import 'live_service.dart';

/// Fase de la conexión de vídeo, ya normalizada para la UI.
enum LiveRtcPhase {
  /// Sin arrancar.
  idle,

  /// Pidiendo cámara/micro y negociando SDP.
  connecting,

  /// Hay medio remoto fluyendo.
  connected,

  /// La conexión se ha caído o no se ha podido establecer.
  failed,

  /// Cerrada por nosotros.
  closed,
}

/// Una llamada de vídeo 1:1 sobre WebRTC, con la señalización en Firestore.
///
/// Decisiones de diseño y su porqué:
///
/// - QUIÉN OFRECE es determinista: `userA` (el uid menor, el mismo criterio de
///   `pairId`) siempre hace la oferta y `userB` responde. Sin un rol fijo, los
///   dos podrían ofertar a la vez ("glare") y la negociación se rompería o
///   habría que implementar perfect negotiation. Como el id de la sesión ya es
///   determinista, el rol sale gratis.
///
/// - Los candidatos ICE se APLICAN EN ORDEN y solo después de tener la
///   descripción remota; los que llegan antes se guardan en una cola. Añadir
///   un candidato sin `remoteDescription` es un error en todas las
///   implementaciones y se traduce en llamadas que no conectan.
///
/// - El vídeo NUNCA toca nuestros servidores. Eso es bueno para la privacidad
///   y obligatorio para el coste, pero implica que la moderación tiene que ser
///   de cliente: ver [LiveModerationSampler].
///
/// - Las credenciales del relé TURN se piden ANTES de crear la conexión y se
///   cachean horas ([LiveTurnCache]). Sin relé la llamada se intenta igual con
///   STUN a secas: conecta en redes domésticas y falla tras NAT simétrico.
class LiveRtcSession {
  LiveRtcSession({
    required LiveService service,
    required this.sessionId,
    required this.selfUid,
    required this.peerUid,
    required this.isCaller,
    MediaStream? localStream,
    this.turnOverride,
    LiveTurnCache? turnCache,
  })  : _service = service,
        _localStream = localStream,
        _turnCache = turnCache ?? LiveTurnCache.instance;

  final LiveService _service;
  final String sessionId;
  final String selfUid;
  final String peerUid;

  /// `true` para `userA` (el que oferta). Ver nota de "glare" arriba.
  final bool isCaller;

  /// Credenciales TURN ya resueltas. Solo se usa en pruebas y en escenarios
  /// donde el llamador ya las tiene: en producción las pide [_turnCache].
  final LiveTurnCredentials? turnOverride;

  /// Caché compartida de credenciales efímeras. Ver [LiveTurnCache]: se piden
  /// UNA vez y valen horas, no una por llamada ni una por candidato ICE.
  final LiveTurnCache _turnCache;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;

  /// Cámara/micro locales. Puede venir ya abierta desde la sala de espera
  /// ([LiveLocalPreview.release]) para no reabrir el dispositivo.
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<LiveSignal>? _signalSub;

  /// Candidatos remotos recibidos antes de tener `remoteDescription`.
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];

  /// Cuántos candidatos del peer ya se han aplicado. La lista de Firestore
  /// solo crece (arrayUnion), así que un índice basta para no repetir.
  int _appliedCandidates = 0;

  bool _remoteDescriptionSet = false;
  bool _answered = false;
  bool _disposed = false;

  final ValueNotifier<LiveRtcPhase> phase =
      ValueNotifier<LiveRtcPhase>(LiveRtcPhase.idle);

  /// Se dispara la PRIMERA vez que llega medio remoto: es el momento en que la
  /// sesión pasa de `ringing` a `active` y arranca el reloj de 3 minutos.
  VoidCallback? onConnected;

  /// La conexión se cayó definitivamente (no reintentamos indefinidamente: la
  /// sesión dura 3 minutos y dejar al usuario mirando una pantalla negra es
  /// peor que cortar y volver a buscar).
  VoidCallback? onFailed;

  /// Estado del micrófono/cámara locales, para pintar los botones.
  final ValueNotifier<bool> micEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> cameraEnabled = ValueNotifier<bool>(true);

  MediaStream? get remoteStream => _remoteStream;

  /// Pista de vídeo REMOTA: la fuente de los fotogramas que se moderan.
  MediaStreamTrack? get remoteVideoTrack {
    final List<MediaStreamTrack>? tracks = _remoteStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return null;
    return tracks.first;
  }

  /// Arranca la llamada: permisos + medio local + negociación.
  ///
  /// Lanza [LiveMediaException] si no hay cámara/micro. El llamador debe
  /// mostrar el porqué, no una pantalla vacía.
  Future<void> start() async {
    if (_disposed) return;
    phase.value = LiveRtcPhase.connecting;

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    // Si la sala de espera ya tenía la cámara abierta, se reutiliza tal cual.
    _localStream ??= await openLiveMedia();
    localRenderer.srcObject = _localStream;

    // TURN ANTES de construir la conexión: los servidores ICE se fijan en el
    // constructor de `RTCPeerConnection` y la recolección de candidatos arranca
    // con la oferta. Pedirlas después no serviría de nada. La caché hace que
    // esto sea una llamada de red cada varias horas, no en cada sesión.
    final LiveTurnCredentials? turn = turnOverride ??
        await _turnCache.obtain(
          () => _service.fetchTurnCredentials(sessionId),
        );
    // La petición es de red: el usuario puede haber colgado mientras tanto.
    if (_disposed) return;

    // Si el relé viene mal configurado, se REINTENTA SIN ÉL en vez de tumbar
    // la llamada. Una URL malformada (un `transport=tls` donde tocaba `tcp`,
    // un `turn:usuario@host` pegado del panel del proveedor) hace fallar el
    // constructor de RTCPeerConnection, y sin este respaldo eso se llevaba por
    // delante el 100% de las videollamadas: también las que hoy funcionan solo
    // con STUN. Sería estrictamente peor que no tener TURN, y encima cada
    // fallo quema el turno de cola de los dos participantes.
    RTCPeerConnection pc;
    try {
      pc = await createPeerConnection(LiveIceConfig.build(turn: turn));
    } catch (error) {
      if (turn == null) rethrow;
      debugPrint(
        '[live] el relé TURN no es utilizable ($error): se reintenta solo '
        'con STUN. Revisa LIVE_TURN_URLS en el backend.',
      );
      // Se tira la credencial: si la URL es mala, volver a pedir la misma en
      // la siguiente sesión repetiría el fallo.
      _turnCache.invalidate();
      if (_disposed) return;
      pc = await createPeerConnection(LiveIceConfig.build());
    }
    _pc = pc;

    // Unified Plan: se añaden PISTAS, no streams.
    for (final MediaStreamTrack track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    pc.onIceCandidate = _publishCandidate;
    pc.onTrack = _onRemoteTrack;
    pc.onConnectionState = _onConnectionState;

    // Escuchar ANTES de ofertar: si el peer ya publicó su SDP (porque llegó
    // primero), no queremos perdérnoslo por una carrera.
    _signalSub = _service.watchSignal(sessionId, peerUid).listen(
          _onPeerSignal,
          onError: (Object _) {
            // Un fallo del canal de señalización deja la llamada sin poder
            // negociar: es un fallo de conexión a todos los efectos.
            _fail();
          },
        );

    if (isCaller) {
      final RTCSessionDescription offer = await pc.createOffer(
        <String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        },
      );
      await pc.setLocalDescription(offer);
      await _service.publishSdp(
        sessionId: sessionId,
        uid: selfUid,
        type: 'offer',
        sdp: offer.sdp ?? '',
      );
    }
  }

  void _publishCandidate(RTCIceCandidate candidate) {
    if (_disposed) return;
    if ((candidate.candidate ?? '').isEmpty) return;
    // Best-effort y sin await: bloquear la recolección ICE por una escritura
    // lenta alargaría el establecimiento de la llamada.
    unawaited(
      _service
          .publishCandidate(
            sessionId: sessionId,
            uid: selfUid,
            candidate: <String, dynamic>{
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          )
          .catchError((Object _) {}),
    );
  }

  void _onRemoteTrack(RTCTrackEvent event) {
    if (_disposed) return;
    if (event.streams.isEmpty) return;
    _remoteStream = event.streams.first;
    remoteRenderer.srcObject = _remoteStream;
    if (phase.value != LiveRtcPhase.connected) {
      phase.value = LiveRtcPhase.connected;
      onConnected?.call();
    }
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    if (_disposed) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        if (phase.value != LiveRtcPhase.connected) {
          phase.value = LiveRtcPhase.connected;
          onConnected?.call();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        // `failed` sin TURN es el síntoma típico del NAT simétrico: los dos
        // extremos recolectaron candidatos pero ninguno es alcanzable.
        _fail();
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        break;
    }
  }

  void _fail() {
    if (_disposed || phase.value == LiveRtcPhase.closed) return;
    if (phase.value == LiveRtcPhase.failed) return;
    phase.value = LiveRtcPhase.failed;
    onFailed?.call();
  }

  Future<void> _onPeerSignal(LiveSignal signal) async {
    final RTCPeerConnection? pc = _pc;
    if (pc == null || _disposed) return;

    if (signal.hasSdp && !_remoteDescriptionSet) {
      final String type = signal.sdpType!;
      // El que oferta solo acepta 'answer' y el que responde solo 'offer'.
      // Aceptar cualquier cosa permitiría a un cliente modificado renegociar
      // la sesión a su gusto en mitad de la llamada.
      final bool expected =
          isCaller ? type == 'answer' : type == 'offer';
      if (expected) {
        try {
          await pc.setRemoteDescription(
            RTCSessionDescription(signal.sdp, type),
          );
          _remoteDescriptionSet = true;
          await _drainPendingCandidates();
          if (!isCaller && !_answered) {
            _answered = true;
            final RTCSessionDescription answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            await _service.publishSdp(
              sessionId: sessionId,
              uid: selfUid,
              type: 'answer',
              sdp: answer.sdp ?? '',
            );
          }
        } catch (error) {
          if (kDebugMode) debugPrint('[live] SDP remoto inválido: $error');
          _fail();
          return;
        }
      }
    }

    // Candidatos nuevos desde el último índice aplicado.
    if (signal.candidates.length > _appliedCandidates) {
      final List<Map<String, dynamic>> fresh =
          signal.candidates.sublist(_appliedCandidates);
      _appliedCandidates = signal.candidates.length;
      for (final Map<String, dynamic> raw in fresh) {
        final RTCIceCandidate candidate = RTCIceCandidate(
          (raw['candidate'] as Object?)?.toString(),
          (raw['sdpMid'] as Object?)?.toString(),
          _asInt(raw['sdpMLineIndex']),
        );
        if (_remoteDescriptionSet) {
          try {
            await pc.addCandidate(candidate);
          } catch (error) {
            if (kDebugMode) debugPrint('[live] candidato ICE rechazado: $error');
          }
        } else {
          _pendingRemoteCandidates.add(candidate);
        }
      }
    }
  }

  Future<void> _drainPendingCandidates() async {
    final RTCPeerConnection? pc = _pc;
    if (pc == null) return;
    for (final RTCIceCandidate candidate in _pendingRemoteCandidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {
        // Un candidato malformado no puede tumbar la llamada.
      }
    }
    _pendingRemoteCandidates.clear();
  }

  /// Silencia/reactiva el micrófono local.
  void toggleMic() {
    final List<MediaStreamTrack>? tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) return;
    final bool next = !micEnabled.value;
    for (final MediaStreamTrack track in tracks) {
      track.enabled = next;
    }
    micEnabled.value = next;
  }

  /// Apaga/enciende la cámara local.
  ///
  /// Apagar la propia cámara NO desactiva la moderación: lo que se modera es
  /// el vídeo del OTRO, y el otro cliente sigue muestreando el nuestro.
  void toggleCamera() {
    final List<MediaStreamTrack>? tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    final bool next = !cameraEnabled.value;
    for (final MediaStreamTrack track in tracks) {
      track.enabled = next;
    }
    cameraEnabled.value = next;
  }

  Future<void> switchCamera() async {
    final List<MediaStreamTrack>? tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {
      // Dispositivos con una sola cámara: no es un error que deba verse.
    }
  }

  /// Cierra todo: pistas, conexión, renderers y señalización.
  ///
  /// Es crítico que la cámara se apague de verdad al salir: dejar la pista
  /// viva mantendría el LED encendido y seguiría emitiendo vídeo a alguien.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    phase.value = LiveRtcPhase.closed;

    await _signalSub?.cancel();
    _signalSub = null;

    try {
      for (final MediaStreamTrack track
          in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _localStream?.dispose();
    } catch (_) {/* la pista ya estaba cerrada */}
    _localStream = null;
    _remoteStream = null;

    try {
      await _pc?.close();
      await _pc?.dispose();
    } catch (_) {/* la conexión ya estaba cerrada */}
    _pc = null;

    try {
      // El setter lanza si el renderer nunca llegó a inicializarse (p. ej. la
      // llamada falló al pedir la cámara), así que va protegido.
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (_) {/* renderer sin inicializar */}
    try {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    } catch (_) {/* renderer ya liberado */}

    // Borra la propia señal: el SDP describe rutas de red del dispositivo.
    await _service.clearSignal(sessionId, selfUid);

    phase.dispose();
    micEnabled.dispose();
    cameraEnabled.dispose();
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
