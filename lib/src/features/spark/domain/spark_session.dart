import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado del ciclo de vida de una sesión de Attra Spark.
enum SparkStatus {
  /// Invitación enviada; esperando que el otro acepte y ambos estén online.
  waiting('waiting'),

  /// Ambos aceptaron y están online: juego en curso.
  active('active'),

  /// Completaron todas las rondas.
  completed('completed'),

  /// Alguien salió / se desconectó (timeout de presencia).
  abandoned('abandoned'),

  /// Caducó (countdown agotado o TTL sin actividad).
  expired('expired');

  const SparkStatus(this.wireName);
  final String wireName;

  bool get isLive => this == SparkStatus.waiting || this == SparkStatus.active;
  bool get isTerminal =>
      this == SparkStatus.completed ||
      this == SparkStatus.abandoned ||
      this == SparkStatus.expired;

  static SparkStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final SparkStatus s in SparkStatus.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return SparkStatus.waiting;
  }
}

/// Presencia + aceptación de un participante en la sala.
class SparkParticipant {
  const SparkParticipant({
    required this.uid,
    required this.accepted,
    required this.lastSeenAt,
  });

  final String uid;
  final bool accepted;
  final DateTime? lastSeenAt;

  /// Online si dio señal de vida dentro de [window] (heartbeat).
  bool onlineWithin(Duration window, {DateTime? now}) {
    final DateTime? seen = lastSeenAt;
    if (seen == null) return false;
    return (now ?? DateTime.now()).difference(seen) <= window;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'accepted': accepted,
        'lastSeenAt': lastSeenAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(lastSeenAt!),
      };

  static SparkParticipant fromMap(String uid, Object? raw) {
    final Map<String, dynamic> m = raw is Map
        ? raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    return SparkParticipant(
      uid: uid,
      accepted: (m['accepted'] as bool?) ?? false,
      lastSeenAt: _asDate(m['lastSeenAt']),
    );
  }
}

/// Una sesión de Attra Spark: `matches/{matchId}/sparkSessions/{sessionId}`.
///
/// Documento ÚNICO que ambos clientes leen en streaming y al que escriben sus
/// respuestas/reacciones/presencia (protegido por reglas: solo participantes del
/// match). Sin escrituras por tecla: solo al enviar respuesta/reacción/heartbeat.
class SparkSession {
  const SparkSession({
    required this.id,
    required this.matchId,
    required this.userAId,
    required this.userBId,
    required this.status,
    required this.invitedBy,
    required this.currentRound,
    required this.totalRounds,
    required this.countdownSeconds,
    required this.participants,
    required this.answers,
    required this.reactions,
    this.summary,
    this.abandonedBy,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.expiresAt,
    this.lastActivityAt,
  });

  final String id;
  final String matchId;

  /// userA = anfitrión (quien creó/invitó); userB = invitado.
  final String userAId;
  final String userBId;

  final SparkStatus status;
  final String invitedBy;
  final int currentRound; // índice 0-based
  final int totalRounds;
  final int countdownSeconds;

  /// uid -> presencia/aceptación.
  final Map<String, SparkParticipant> participants;

  /// roundId -> (uid -> valor de respuesta).
  final Map<String, Map<String, dynamic>> answers;

  /// roundId -> (uid -> reacción).
  final Map<String, Map<String, dynamic>> reactions;

  /// Resumen final (coincidencias, temas, primera pregunta). Null hasta el fin.
  final Map<String, dynamic>? summary;

  final String? abandonedBy;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt;
  final DateTime? lastActivityAt;

  bool involves(String uid) => uid == userAId || uid == userBId;
  String otherUid(String uid) => uid == userAId ? userBId : userAId;
  bool isHostUid(String uid) => uid == userAId;

  /// ¿Ambos aceptaron?
  bool get bothAccepted =>
      (participants[userAId]?.accepted ?? false) &&
      (participants[userBId]?.accepted ?? false);

  /// ¿Ambos online dentro de [window]?
  bool bothOnline(Duration window, {DateTime? now}) =>
      (participants[userAId]?.onlineWithin(window, now: now) ?? false) &&
      (participants[userBId]?.onlineWithin(window, now: now) ?? false);

  /// Respuesta de [uid] en [roundId] (o null).
  Object? answerOf(String roundId, String uid) => answers[roundId]?[uid];

  /// ¿[uid] ya respondió la ronda [roundId]?
  bool hasAnswered(String roundId, String uid) =>
      answers[roundId]?.containsKey(uid) ?? false;

  /// ¿Ambos respondieron la ronda [roundId]?
  bool bothAnswered(String roundId) =>
      hasAnswered(roundId, userAId) && hasAnswered(roundId, userBId);

  /// Segundos restantes del countdown (>=0). 0 si ya terminó.
  int remainingSeconds({DateTime? now}) {
    final DateTime? exp = expiresAt;
    if (exp == null) return countdownSeconds;
    final int s = exp.difference(now ?? DateTime.now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  factory SparkSession.fromMap(String id, Map<String, dynamic> map) {
    Map<String, Map<String, dynamic>> nested(Object? raw) {
      if (raw is! Map) return <String, Map<String, dynamic>>{};
      final Map<String, Map<String, dynamic>> out =
          <String, Map<String, dynamic>>{};
      raw.forEach((dynamic k, dynamic v) {
        if (v is Map) {
          out[k.toString()] =
              v.map((dynamic kk, dynamic vv) => MapEntry(kk.toString(), vv));
        }
      });
      return out;
    }

    final Map<String, SparkParticipant> parts = <String, SparkParticipant>{};
    final Object? rawParts = map['participants'];
    if (rawParts is Map) {
      rawParts.forEach((dynamic k, dynamic v) {
        parts[k.toString()] = SparkParticipant.fromMap(k.toString(), v);
      });
    }

    return SparkSession(
      id: id,
      matchId: (map['matchId'] as String?) ?? '',
      userAId: (map['userAId'] as String?) ?? '',
      userBId: (map['userBId'] as String?) ?? '',
      status: SparkStatus.fromValue(map['status']),
      invitedBy: (map['invitedBy'] as String?) ?? (map['userAId'] as String?) ?? '',
      currentRound: (map['currentRound'] as num?)?.toInt() ?? 0,
      totalRounds: (map['totalRounds'] as num?)?.toInt() ?? 0,
      countdownSeconds: (map['countdownSeconds'] as num?)?.toInt() ?? 300,
      participants: parts,
      answers: nested(map['answers']),
      reactions: nested(map['reactions']),
      summary: map['summary'] is Map
          ? (map['summary'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
          : null,
      abandonedBy: map['abandonedBy'] as String?,
      createdAt: _asDate(map['createdAt']),
      startedAt: _asDate(map['startedAt']),
      endedAt: _asDate(map['endedAt']),
      expiresAt: _asDate(map['expiresAt']),
      lastActivityAt: _asDate(map['lastActivityAt']),
    );
  }
}

DateTime? _asDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
