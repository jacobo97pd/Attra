import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/spark_round.dart';
import '../domain/spark_session.dart';

/// Acceso a datos de Attra Spark sobre `matches/{matchId}/sparkSessions/{id}`.
///
/// Escrituras del cliente protegidas por reglas (solo participantes del match).
/// El doc de sesión es ÚNICO por partida y ambos clientes lo leen en streaming;
/// solo se escribe en eventos discretos (aceptar, responder, reaccionar,
/// heartbeat, avanzar) para no saturar Firestore.
class SparkRepository {
  SparkRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  static const String icebreakerSessionId = 'icebreaker_v1';

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sessions(String matchId) =>
      _firestore.collection('matches').doc(matchId).collection('sparkSessions');

  /// Observa la sesión viva (waiting/active) del match, o null si no hay.
  /// whereIn sobre un solo campo no requiere índice compuesto.
  Stream<SparkSession?> watchActiveSession(String matchId) {
    return _sessions(matchId)
        .where('status', whereIn: <String>[
          SparkStatus.waiting.wireName,
          SparkStatus.active.wireName,
        ])
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
          if (snap.docs.isEmpty) return null;
          final QueryDocumentSnapshot<Map<String, dynamic>> d = snap.docs.first;
          return SparkSession.fromMap(d.id, d.data());
        });
  }

  /// Observa una sesión concreta (incluye estados terminales, para el resumen).
  Stream<SparkSession?> watchSession(String matchId, String sessionId) {
    return _sessions(matchId).doc(sessionId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? SparkSession.fromMap(d.id, d.data()!) : null);
  }

  Future<SparkSession?> fetchActiveSession(String matchId) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _sessions(matchId)
        .where('status', whereIn: <String>[
          SparkStatus.waiting.wireName,
          SparkStatus.active.wireName,
        ])
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final QueryDocumentSnapshot<Map<String, dynamic>> d = snap.docs.first;
    return SparkSession.fromMap(d.id, d.data());
  }

  /// Observa cualquier sesión de Spark del match. Producto: Spark es un
  /// rompehielos de una sola vez por match, así que cualquier doc bloquea otra
  /// invitación.
  Stream<SparkSession?> watchAnySession(String matchId) {
    return _sessions(matchId)
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      if (snap.docs.isEmpty) return null;
      final QueryDocumentSnapshot<Map<String, dynamic>> d = snap.docs.first;
      return SparkSession.fromMap(d.id, d.data());
    });
  }

  Future<SparkSession?> fetchAnySession(String matchId) async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _sessions(matchId).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final QueryDocumentSnapshot<Map<String, dynamic>> d = snap.docs.first;
    return SparkSession.fromMap(d.id, d.data());
  }

  /// Crea una sesión `waiting`. El invitador queda aceptado de inicio.
  Future<String> createSession({
    required String matchId,
    required String hostUid,
    required String guestUid,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _sessions(matchId).doc(icebreakerSessionId);
    await _firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> existing = await tx.get(ref);
      if (existing.exists) {
        throw const SparkSessionAlreadyExistsException();
      }
      tx.set(ref, <String, dynamic>{
        'matchId': matchId,
        'userAId': hostUid,
        'userBId': guestUid,
        'invitedBy': hostUid,
        'status': SparkStatus.waiting.wireName,
        'currentRound': 0,
        'totalRounds': SparkRoundCatalog.totalRounds,
        'countdownSeconds': 300,
        'participants': <String, dynamic>{
          hostUid: <String, dynamic>{
            'accepted': true,
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          guestUid: <String, dynamic>{
            'accepted': false,
            'lastSeenAt': null,
          },
        },
        'answers': <String, dynamic>{},
        'reactions': <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    });
    return ref.id;
  }

  /// Merge parcial sobre el doc (deep-merge para mapas anidados).
  Future<void> patch(
      String matchId, String sessionId, Map<String, dynamic> data) async {
    await _sessions(matchId).doc(sessionId).set(data, SetOptions(merge: true));
  }

  /// Heartbeat de presencia (campo puntual, escritura mínima).
  Future<void> heartbeat(String matchId, String sessionId, String uid) async {
    await _sessions(matchId).doc(sessionId).set(<String, dynamic>{
      'participants': <String, dynamic>{
        uid: <String, dynamic>{'lastSeenAt': FieldValue.serverTimestamp()},
      },
    }, SetOptions(merge: true));
  }
}

class SparkSessionAlreadyExistsException implements Exception {
  const SparkSessionAlreadyExistsException();
}
