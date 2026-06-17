import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/spark_round.dart';
import '../domain/spark_session.dart';
import '../domain/spark_summary.dart';
import 'spark_analytics.dart';
import 'spark_repository.dart';

class SparkAlreadyPlayedException implements Exception {
  const SparkAlreadyPlayedException();

  String get message => 'Ya habéis jugado Attra Spark en este match.';
}

/// Orquestación de Attra Spark. Mantiene la máquina de estados de la sesión y
/// es la ÚNICA puerta de escritura desde la UI. El chat NO se toca aquí salvo el
/// mensaje de sistema final, que va por Cloud Function (los mensajes de chat son
/// backend-only). Si la función no está desplegada, el juego sigue funcionando
/// y solo se omite el mensaje automático en el chat.
class SparkService {
  SparkService({
    required SparkRepository repository,
    required SparkAnalytics analytics,
    required FirebaseFunctions functions,
  })  : _repo = repository,
        _analytics = analytics,
        _functions = functions;

  final SparkRepository _repo;
  final SparkAnalytics _analytics;
  final FirebaseFunctions _functions;

  /// Ventana de presencia: se considera online si hubo heartbeat reciente.
  static const Duration presenceWindow = Duration(seconds: 35);

  // --- Lecturas ---
  Stream<SparkSession?> watchActiveSession(String matchId) =>
      _repo.watchActiveSession(matchId);
  Stream<SparkSession?> watchAnySession(String matchId) =>
      _repo.watchAnySession(matchId);
  Stream<SparkSession?> watchSession(String matchId, String sessionId) =>
      _repo.watchSession(matchId, sessionId);
  Future<SparkSession?> fetchActiveSession(String matchId) =>
      _repo.fetchActiveSession(matchId);
  Future<SparkSession?> fetchAnySession(String matchId) =>
      _repo.fetchAnySession(matchId);

  // --- Ciclo de vida ---

  /// Invita: crea la sesión (waiting) con el invitador ya aceptado.
  Future<String> invite({
    required String matchId,
    required String hostUid,
    required String guestUid,
  }) async {
    // Reutiliza una sesión viva si ya existe (evita duplicados).
    final SparkSession? existing = await _repo.fetchActiveSession(matchId);
    if (existing != null) return existing.id;
    final SparkSession? played = await _repo.fetchAnySession(matchId);
    if (played != null) throw const SparkAlreadyPlayedException();

    final String id;
    try {
      id = await _repo.createSession(
        matchId: matchId,
        hostUid: hostUid,
        guestUid: guestUid,
      );
    } on SparkSessionAlreadyExistsException {
      throw const SparkAlreadyPlayedException();
    }
    _analytics.log(SparkAnalytics.invited,
        uid: hostUid, matchId: matchId, sessionId: id);
    return id;
  }

  /// Acepta la invitación. Si con esto ambos han aceptado, arranca el juego.
  Future<void> accept(
      {required SparkSession session, required String uid}) async {
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'participants': <String, dynamic>{
        uid: <String, dynamic>{
          'accepted': true,
          'lastSeenAt': FieldValue.serverTimestamp(),
        },
      },
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    _analytics.log(SparkAnalytics.accepted,
        uid: uid, matchId: session.matchId, sessionId: session.id);

    // El invitador ya aceptó al crear; si acepta el invitado, ya están ambos.
    final bool willBothAccept = uid == session.userBId || session.bothAccepted;
    if (session.status == SparkStatus.waiting && willBothAccept) {
      await _start(session);
    }
  }

  Future<void> _start(SparkSession session) async {
    final DateTime now = DateTime.now();
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'status': SparkStatus.active.wireName,
      'currentRound': 0,
      'startedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
          now.add(Duration(seconds: session.countdownSeconds))),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    _analytics.log(SparkAnalytics.started,
        uid: session.invitedBy,
        matchId: session.matchId,
        sessionId: session.id);
  }

  /// Heartbeat de presencia (la UI lo llama periódicamente, ~cada 20s).
  Future<void> heartbeat(SparkSession session, String uid) =>
      _repo.heartbeat(session.matchId, session.id, uid);

  /// Guarda la respuesta de [uid] en la ronda [roundId]. [value] puede ser una
  /// clave (String) o un mapa (p. ej. {choice, guess} en "Adivina al otro").
  Future<void> submitAnswer({
    required SparkSession session,
    required String uid,
    required String roundId,
    required Object value,
  }) async {
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'answers': <String, dynamic>{
        roundId: <String, dynamic>{uid: value},
      },
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reacción rápida de [uid] en la ronda [roundId].
  Future<void> submitReaction({
    required SparkSession session,
    required String uid,
    required String roundId,
    required String reaction,
  }) async {
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'reactions': <String, dynamic>{
        roundId: <String, dynamic>{uid: reaction},
      },
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

  /// Avanza de ronda. SOLO el anfitrión (userA) avanza, para evitar carreras.
  /// Si era la última, completa la sesión. Llamar cuando ambos respondieron.
  Future<void> advanceIfHost({
    required SparkSession session,
    required String uid,
    required List<SparkRound> rounds,
    String hostName = 'Tú',
    String guestName = 'tu match',
  }) async {
    if (uid != session.userAId) return; // solo el anfitrión orquesta
    final int next = session.currentRound + 1;
    if (next >= session.totalRounds) {
      await complete(
          session: session,
          rounds: rounds,
          hostName: hostName,
          guestName: guestName);
      return;
    }
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'currentRound': next,
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    _analytics.log(SparkAnalytics.roundCompleted,
        uid: uid,
        matchId: session.matchId,
        sessionId: session.id,
        extra: <String, dynamic>{'round': session.currentRound});
  }

  /// Completa la sesión: genera resumen local, lo guarda y pide al backend que
  /// inserte el mensaje de sistema en el chat (best-effort).
  Future<void> complete({
    required SparkSession session,
    required List<SparkRound> rounds,
    String hostName = 'Tú',
    String guestName = 'tu match',
  }) async {
    final SparkSummary summary = SparkSummaryBuilder.build(
      session: session,
      rounds: rounds,
      nameA: hostName,
      nameB: guestName,
    );
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'status': SparkStatus.completed.wireName,
      'summary': summary.toMap(),
      'endedAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    _analytics.log(SparkAnalytics.completed,
        uid: session.userAId, matchId: session.matchId, sessionId: session.id);

    // Mensaje de sistema en el chat (backend-only). Best-effort.
    try {
      await _functions.httpsCallable('completeSparkSession').call<dynamic>(
        <String, dynamic>{
          'matchId': session.matchId,
          'sessionId': session.id,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Spark: completeSparkSession no disponible -> $e');
      }
    }
  }

  /// Abandona: marca la sesión como abandonada por [uid].
  Future<void> abandon(
      {required SparkSession session, required String uid}) async {
    if (session.status.isTerminal) return;
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'status': SparkStatus.abandoned.wireName,
      'abandonedBy': uid,
      'endedAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
    _analytics.log(SparkAnalytics.abandoned,
        uid: uid, matchId: session.matchId, sessionId: session.id);
  }

  /// Marca como caducada (countdown agotado / sin actividad). Solo anfitrión.
  Future<void> expireIfHost(
      {required SparkSession session, required String uid}) async {
    if (uid != session.userAId || session.status.isTerminal) return;
    await _repo.patch(session.matchId, session.id, <String, dynamic>{
      'status': SparkStatus.expired.wireName,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Analytics auxiliares (post-juego) ---
  void logChatOpenedAfter(
          {required String uid, String? matchId, String? sessionId}) =>
      _analytics.log(SparkAnalytics.chatOpenedAfter,
          uid: uid, matchId: matchId, sessionId: sessionId);

  void logPlanSuggestedAfter(
          {required String uid, String? matchId, String? sessionId}) =>
      _analytics.log(SparkAnalytics.planSuggestedAfter,
          uid: uid, matchId: matchId, sessionId: sessionId);
}
