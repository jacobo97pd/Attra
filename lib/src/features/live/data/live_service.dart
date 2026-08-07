import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/live_constants.dart';
import '../domain/live_session.dart';
import '../domain/live_strikes.dart';
import 'live_rtc_config.dart';

/// Error de una operación del feed en vivo. Envuelve
/// [FirebaseFunctionsException] para que la UI no tenga que conocer Firebase.
class LiveServiceException implements Exception {
  const LiveServiceException(this.message, {this.code});

  final String message;
  final String? code;

  /// El backend nos veta el vivo (strikes). La UI lo trata distinto de un
  /// error técnico: no es un fallo, es una sanción.
  bool get isBlocked =>
      code == 'permission-denied' || code == 'failed-precondition';

  @override
  String toString() => 'LiveServiceException($code): $message';
}

/// Respuesta de `joinLiveQueue`.
///
/// El backend puede emparejar EN EL MISMO momento de entrar (cuando ya había
/// alguien esperando), así que la llamada devuelve el `sessionId` si lo hubo.
/// No dependemos solo de eso: también escuchamos Firestore, porque el otro
/// lado se entera por el listener y no por la respuesta de su callable.
class LiveQueueTicket {
  const LiveQueueTicket({
    required this.waiting,
    this.sessionId,
    this.blockedUntil,
    this.permanentlyBlocked = false,
  });

  final bool waiting;
  final String? sessionId;
  final DateTime? blockedUntil;
  final bool permanentlyBlocked;

  bool get isPaired => (sessionId ?? '').isNotEmpty;
  bool get isBlocked => permanentlyBlocked || blockedUntil != null;

  factory LiveQueueTicket.fromMap(Map<String, dynamic> map) {
    final String? id = (map['sessionId'] as Object?)?.toString();
    return LiveQueueTicket(
      waiting: map['status']?.toString() == 'waiting' ||
          (id == null || id.isEmpty),
      sessionId: (id ?? '').isEmpty ? null : id,
      blockedUntil: liveDateFromValue(map['blockedUntil']),
      permanentlyBlocked: map['permanentlyBlocked'] == true,
    );
  }
}

/// Resultado de sondear `findLiveMatch`.
///
/// El emparejamiento NO ocurre al entrar en la cola: `joinLiveQueue` solo
/// apunta, y es este sondeo el que intenta cruzar candidatos. Por eso el
/// cliente tiene que preguntar periódicamente mientras espera.
class LiveMatchPoll {
  const LiveMatchPoll({
    required this.paired,
    this.sessionId,
    this.peerUid,
    this.isCaller = false,
  });

  final bool paired;
  final String? sessionId;
  final String? peerUid;

  /// Quién crea la oferta WebRTC. Lo decide el servidor (siempre `userA`) para
  /// que los dos clientes tomen el mismo rol sin negociarlo y no haya "glare".
  final bool isCaller;

  factory LiveMatchPoll.fromMap(Map<String, dynamic> map) {
    final String id = (map['sessionId'] as Object?)?.toString() ?? '';
    return LiveMatchPoll(
      paired: map['paired'] == true && id.isNotEmpty,
      sessionId: id.isEmpty ? null : id,
      peerUid: (map['peerUid'] as Object?)?.toString(),
      isCaller: map['isCaller'] == true,
    );
  }
}

/// Resultado de `submitLiveVerdict`.
///
/// El cruce de veredictos y el `writeMatchAndChat` los hace el BACKEND: es la
/// única forma de que dos clientes no puedan fabricarse un match. Aquí solo
/// leemos lo que decidió.
class LiveVerdictResult {
  const LiveVerdictResult({
    required this.outcome,
    this.matchId,
    this.chatId,
  });

  /// 'matched' | 'liked' | 'passed' | 'ignored'.
  ///
  /// `ignored` cuando la sesión se cortó por moderación o denuncia: ahí el
  /// veredicto NO puede acabar en match por mucho que el cliente lo mande.
  final String outcome;
  final String? matchId;
  final String? chatId;

  bool get matched => outcome == 'matched';
  bool get ignored => outcome == 'ignored';

  factory LiveVerdictResult.fromMap(Map<String, dynamic> map) {
    return LiveVerdictResult(
      outcome: (map['outcome'] as Object?)?.toString() ?? 'ignored',
      matchId: (map['matchId'] as Object?)?.toString(),
      chatId: (map['chatId'] as Object?)?.toString(),
    );
  }
}

/// Resultado de `reviewLiveFrame` (SafeSearch sobre el fotograma REMOTO).
class LiveModerationResult {
  const LiveModerationResult({
    required this.outcome,
    required this.strike,
    required this.endSession,
    this.reason = '',
  });

  /// 'clean' | 'violation' | 'unreviewable' | 'ignored'.
  final String outcome;

  /// Hubo sanción para el OTRO. El backend NO nos dice su recuento: sería
  /// información sobre un tercero.
  final bool strike;

  /// El backend ordena cortar YA. El corte por moderación es inmediato para
  /// ambos: no esperamos a que el barrido cierre la sesión.
  final bool endSession;

  final String reason;

  bool get flagged => outcome == 'violation';

  static const LiveModerationResult clean = LiveModerationResult(
    outcome: 'clean',
    strike: false,
    endSession: false,
  );

  factory LiveModerationResult.fromMap(Map<String, dynamic> map) {
    return LiveModerationResult(
      outcome: (map['outcome'] as Object?)?.toString() ?? 'clean',
      strike: map['strike'] == true,
      endSession: map['endSession'] == true,
      reason: (map['reason'] as Object?)?.toString() ?? '',
    );
  }
}

/// Señal WebRTC del OTRO participante: `liveSessions/{id}/signals/{uid}`.
///
/// Es transporte puro (no dominio): la oferta/respuesta SDP y los candidatos
/// ICE que el peer ha publicado. Cada uno escribe SOLO su documento; leer el
/// ajeno es lo que hace de canal de señalización.
class LiveSignal {
  const LiveSignal({
    this.sdpType,
    this.sdp,
    this.candidates = const <Map<String, dynamic>>[],
  });

  /// 'offer' | 'answer'.
  final String? sdpType;
  final String? sdp;

  /// Candidatos ICE en orden de publicación. El consumidor lleva su propio
  /// índice: la lista solo CRECE (append), nunca se reordena, así que basta
  /// con recordar cuántos se han aplicado ya.
  final List<Map<String, dynamic>> candidates;

  bool get hasSdp => (sdp ?? '').isNotEmpty && (sdpType ?? '').isNotEmpty;

  static const LiveSignal empty = LiveSignal();

  factory LiveSignal.fromMap(Map<String, dynamic> map) {
    final Object? rawSdp = map['sdp'];
    String? type;
    String? description;
    if (rawSdp is Map) {
      type = (rawSdp['type'] as Object?)?.toString();
      description = (rawSdp['sdp'] as Object?)?.toString();
    }
    final Object? rawCandidates = map['candidates'];
    return LiveSignal(
      sdpType: type,
      sdp: description,
      candidates: rawCandidates is List
          ? rawCandidates
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> e) => e.map(
                    (Object? k, Object? v) => MapEntry<String, dynamic>(
                      k.toString(),
                      v,
                    ),
                  ))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
    );
  }
}

/// Capa de datos del FEED EN VIVO.
///
/// Reparto de responsabilidades, a propósito:
/// - Todo lo que decide algo (emparejar, cruzar veredictos, sancionar) va por
///   CALLABLE: el backend es la autoridad y un cliente modificado no puede
///   saltárselo.
/// - Solo la señalización WebRTC se escribe directo a Firestore, porque es un
///   canal punto a punto entre los dos participantes y meter un salto por
///   Cloud Functions en cada candidato ICE añadiría cientos de milisegundos al
///   establecimiento de la llamada.
class LiveService {
  LiveService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  // --- Cola ---

  /// Entra en la cola. Idempotente: volver a llamar con una entrada viva NO
  /// debe reiniciar `joinedAt` (o se perdería el turno de quien lleva más
  /// tiempo esperando). El cliente reintenta si tarda, y cuenta con ello.
  Future<LiveQueueTicket> joinQueue() async {
    final Map<String, dynamic> data =
        await _call('joinLiveQueue', <String, dynamic>{});
    return LiveQueueTicket.fromMap(data);
  }

  /// Sondea el emparejamiento.
  ///
  /// Entrar en la cola solo APUNTA; es este sondeo el que busca candidatos
  /// compatibles y crea la sesión. Hay que llamarlo periódicamente mientras se
  /// espera: además de emparejar, refresca la señal de vida de la entrada (el
  /// backend descarta como zombis las que llevan rato sin sondear, porque
  /// emparejarse con un móvil que ya no escucha gasta el turno de los dos).
  Future<LiveMatchPoll> findMatch() async {
    final Map<String, dynamic> data =
        await _call('findLiveMatch', <String, dynamic>{});
    return LiveMatchPoll.fromMap(data);
  }

  /// Sale de la cola. Se llama SIEMPRE al abandonar la pantalla: dejar
  /// entradas huérfanas emparejaría a alguien con un móvil que ya no escucha.
  Future<void> leaveQueue() async {
    await _call('leaveLiveQueue', <String, dynamic>{});
  }

  /// Estado de la propia entrada en cola (`waiting` / `paired`). Solo lectura:
  /// el documento lo escribe el backend.
  Stream<String?> watchQueueStatus(String uid) {
    return _firestore
        .collection(LiveCollections.queue)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return null;
      return (snap.data() ?? const <String, dynamic>{})['status']?.toString();
    });
  }

  // --- Sesión ---

  // NOTA: descubrir la sesión NO se hace con una consulta
  // `liveSessions.where('users', arrayContains: uid)`. Sería lo natural, pero
  // el backend no borra las sesiones terminadas (las conserva como registro),
  // así que esa consulta iría creciendo con el historial del usuario y cada
  // apertura de la pantalla descargaría todas sus llamadas pasadas. El
  // descubrimiento va por `findMatch()`, que además es lo que el emparejador
  // espera. Aquí solo seguimos el documento CONCRETO de la sesión en curso.

  Stream<LiveSession?> watchSession(String sessionId) {
    return _firestore
        .collection(LiveCollections.sessions)
        .doc(sessionId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return null;
      return LiveSession.fromMap(snap.id, snap.data() ?? <String, dynamic>{});
    });
  }

  Future<LiveSession?> fetchSession(String sessionId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _firestore
        .collection(LiveCollections.sessions)
        .doc(sessionId)
        .get();
    if (!snap.exists) return null;
    return LiveSession.fromMap(snap.id, snap.data() ?? <String, dynamic>{});
  }

  /// Pasa la sesión de `ringing` a `active`.
  ///
  /// Lo dispara el cliente porque el vídeo es peer-to-peer y el servidor NO
  /// puede saber cuándo se estableció la conexión. El backend lo aplica de
  /// forma idempotente (primer aviso gana) y es ÉL quien fija `startedAt` y
  /// `endsAt`: el tope de 3 minutos no puede depender del reloj del móvil.
  Future<void> markActive(String sessionId) async {
    await _call('startLiveSession', <String, dynamic>{'sessionId': sessionId});
  }

  /// Cierra la sesión. El primer cierre gana; el segundo es un no-op.
  ///
  /// Del cliente el backend solo acepta `left` y `reported`: `timeout`,
  /// `moderation` y `matched` los pone ÉL, para que nadie pueda fabricar un
  /// cierre "por moderación" contra otra persona.
  ///
  /// Con `reported`, el backend crea el reporte en la MISMA cola que
  /// `reportUser` y escribe dislike en los dos sentidos. Por eso el motivo del
  /// reporte viaja aquí y no en una llamada aparte: una sola operación, un
  /// solo reporte.
  Future<void> endSession(
    String sessionId,
    LiveEndReason reason, {
    String? reportReason,
    String details = '',
  }) async {
    await _call('endLiveSession', <String, dynamic>{
      'sessionId': sessionId,
      'reason': reason.wireName,
      if (reportReason != null && reportReason.isNotEmpty)
        'reportReason': reportReason,
      if (details.trim().isNotEmpty) 'details': details.trim(),
    });
  }

  /// Envía el veredicto. Si el cruce da like+like, el backend crea match y
  /// chat con `writeMatchAndChat` (mismo camino que el resto de la app) y un
  /// `pass` escribe el dislike correspondiente.
  Future<LiveVerdictResult> submitVerdict(
    String sessionId,
    LiveVerdict verdict,
  ) async {
    final Map<String, dynamic> data =
        await _call('submitLiveVerdict', <String, dynamic>{
      'sessionId': sessionId,
      'verdict': verdict.wireName,
    });
    return LiveVerdictResult.fromMap(data);
  }

  /// Veredicto propio ya registrado (para no volver a pedirlo tras reabrir).
  Stream<LiveVerdict?> watchVerdict(String sessionId, String uid) {
    return _firestore
        .collection(LiveCollections.sessions)
        .doc(sessionId)
        .collection(LiveCollections.verdicts)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return null;
      return LiveVerdict.tryFromValue(
        (snap.data() ?? const <String, dynamic>{})['verdict'],
      );
    });
  }

  // --- Señalización WebRTC ---

  /// Publica la oferta/respuesta SDP propia en `signals/{uid}`.
  ///
  /// `merge` para no pisar los candidatos ICE que ya se hubieran publicado:
  /// el SDP y los candidatos viajan por el mismo documento pero en momentos
  /// distintos.
  Future<void> publishSdp({
    required String sessionId,
    required String uid,
    required String type,
    required String sdp,
  }) async {
    await _signalDoc(sessionId, uid).set(<String, dynamic>{
      'sdp': <String, dynamic>{'type': type, 'sdp': sdp},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Añade un candidato ICE propio.
  ///
  /// `arrayUnion` porque los dos extremos van escribiendo a ritmos distintos y
  /// una escritura completa del array perdería candidatos por carrera.
  Future<void> publishCandidate({
    required String sessionId,
    required String uid,
    required Map<String, dynamic> candidate,
  }) async {
    await _signalDoc(sessionId, uid).set(<String, dynamic>{
      'candidates': FieldValue.arrayUnion(<Object>[candidate]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Señal del OTRO participante.
  Stream<LiveSignal> watchSignal(String sessionId, String peerUid) {
    return _signalDoc(sessionId, peerUid).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!snap.exists) return LiveSignal.empty;
        return LiveSignal.fromMap(snap.data() ?? <String, dynamic>{});
      },
    );
  }

  /// Borra la propia señal al colgar.
  ///
  /// PORQUÉ: el SDP describe rutas de red del dispositivo (IPs locales, y sin
  /// TURN también la pública). No tiene ningún valor una vez terminada la
  /// llamada y sí un coste de privacidad si se queda ahí. Best-effort: si
  /// falla no rompemos el cierre.
  Future<void> clearSignal(String sessionId, String uid) async {
    try {
      await _signalDoc(sessionId, uid).delete();
    } catch (_) {
      // El documento puede no existir o el backend haber cerrado ya la sesión.
    }
  }

  DocumentReference<Map<String, dynamic>> _signalDoc(
    String sessionId,
    String uid,
  ) {
    return _firestore
        .collection(LiveCollections.sessions)
        .doc(sessionId)
        .collection(LiveCollections.signals)
        .doc(uid);
  }

  // --- Sanciones ---

  /// Strikes propios. Comprobarlo en cliente es CORTESÍA (mensaje claro), no
  /// la defensa: quien empareja es el servidor y él vuelve a mirarlo.
  Stream<LiveStrikes> watchStrikes(String uid) {
    return _firestore
        .collection(LiveCollections.strikes)
        .doc(uid)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return LiveStrikes.clean(uid);
      return LiveStrikes.fromMap(uid, snap.data() ?? <String, dynamic>{});
    });
  }

  Future<LiveStrikes> fetchStrikes(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _firestore.collection(LiveCollections.strikes).doc(uid).get();
      if (!snap.exists) return LiveStrikes.clean(uid);
      return LiveStrikes.fromMap(uid, snap.data() ?? <String, dynamic>{});
    } catch (_) {
      // Sin poder leer las sanciones NO bloqueamos: el backend lo hará al
      // intentar entrar en cola. Fallar aquí solo daría un mensaje peor.
      return LiveStrikes.clean(uid);
    }
  }

  // --- Moderación ---

  /// Manda a revisar un fotograma del vídeo REMOTO.
  ///
  /// Es deliberadamente el flujo AJENO y no el propio: si cada cliente
  /// moderase su propia cámara, bastaría con un cliente modificado para
  /// desactivar la moderación. Moderando el del otro, el infractor no puede
  /// impedir que le denuncien.
  Future<LiveModerationResult> reviewFrame({
    required String sessionId,
    required String targetUid,
    required String imageBase64,
  }) async {
    final Map<String, dynamic> data =
        await _call('reviewLiveFrame', <String, dynamic>{
      'sessionId': sessionId,
      'targetUid': targetUid,
      'imageBase64': imageBase64,
    });
    return LiveModerationResult.fromMap(data);
  }

  // --- Relé TURN ---

  /// Pide credenciales TURN EFÍMERAS al backend.
  ///
  /// El secreto compartido no sale nunca de Functions: aquí llegan un usuario y
  /// una clave que caducan en horas (ver [LiveTurnCredentials] y
  /// functions/src/liveTurn.ts). Devuelve `null` cuando todavía no hay relé
  /// contratado; quien llama es [LiveTurnCache], que cachea y hace el backoff.
  /// El backend ya no emite relé a cualquiera que esté autenticado: exige una
  /// sesión de vivo real en la que participes. Sin eso, una cuenta desechable
  /// podía pedir credenciales en bucle y usar el relé —que se paga por GB—
  /// como proxy genérico sin entrar jamás al vídeo.
  Future<LiveTurnCredentials?> fetchTurnCredentials(String sessionId) async {
    final Map<String, dynamic> data = await _call(
      'getLiveTurnCredentials',
      <String, dynamic>{'sessionId': sessionId},
    );
    return LiveTurnCredentials.fromCallable(data);
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (error) {
      throw LiveServiceException(error.message ?? error.code,
          code: error.code);
    }
  }
}
