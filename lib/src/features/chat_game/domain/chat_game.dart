import 'package:cloud_firestore/cloud_firestore.dart';

/// "Duelo de Química" (5-Minute Spark): reto de conversación de 5 min dentro del
/// chat entre dos personas que ya han hecho match. Backend-autoritativo: el
/// cliente solo lanza acciones (start/respond/finish/abandon) vía Cloud
/// Functions; el estado y el resultado de la IA los escribe el backend.
///
/// Vive en `chats/{chatId}/gameSessions/{sessionId}`.

/// Ciclo de vida de una sesión de juego.
enum ChatGameStatus {
  /// Invitación enviada; esperando que el invitado acepte/rechace.
  pending('pending'),

  /// Aceptado por ambos; a punto de empezar (transitorio).
  accepted('accepted'),

  /// Reto en curso: cuenta atrás de 5 min corriendo.
  active('active'),

  /// Terminó y la IA ya emitió resultado.
  completed('completed'),

  /// Rechazado o cancelado antes de empezar.
  cancelled('cancelled'),

  /// Alguien abandonó el reto en curso (sin penalización).
  abandoned('abandoned');

  const ChatGameStatus(this.wireName);
  final String wireName;

  bool get isPending => this == ChatGameStatus.pending;
  bool get isActive => this == ChatGameStatus.active;
  bool get isCompleted => this == ChatGameStatus.completed;
  bool get isTerminal =>
      this == ChatGameStatus.completed ||
      this == ChatGameStatus.cancelled ||
      this == ChatGameStatus.abandoned;

  static ChatGameStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final ChatGameStatus s in ChatGameStatus.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return ChatGameStatus.pending;
  }
}

/// Modalidad del juego. `coffeeChallenge` (Reto Café) requiere consentimiento
/// EXPLÍCITO de ambos y solo cambia el texto del premio (quién invita al café);
/// nunca obliga a pagar nada fuera de la app.
enum ChatGameMode {
  normal('normal'),
  coffeeChallenge('coffee_challenge');

  const ChatGameMode(this.wireName);
  final String wireName;

  bool get isCoffee => this == ChatGameMode.coffeeChallenge;

  static ChatGameMode fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final ChatGameMode m in ChatGameMode.values) {
      if (m.wireName == raw || m.name == raw) return m;
    }
    return ChatGameMode.normal;
  }
}

/// Sugerencia de quién propone/invita (solo dinámica divertida, sin obligación).
enum PayerSuggestion {
  winnerChooses('winner_chooses'),
  loserInvites('loser_invites'),
  split('split'),
  none('none');

  const PayerSuggestion(this.wireName);
  final String wireName;

  static PayerSuggestion fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final PayerSuggestion p in PayerSuggestion.values) {
      if (p.wireName == raw || p.name == raw) return p;
    }
    return PayerSuggestion.none;
  }
}

/// Plan de cita sugerido por la IA (siempre lugares públicos, sin presión).
class SuggestedDatePlan {
  const SuggestedDatePlan({
    required this.title,
    required this.description,
    required this.placeType,
    this.payerSuggestion = PayerSuggestion.none,
  });

  final String title;
  final String description;
  final String placeType;
  final PayerSuggestion payerSuggestion;

  factory SuggestedDatePlan.fromMap(Map<String, dynamic> map) {
    return SuggestedDatePlan(
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      placeType: (map['placeType'] as String?) ?? '',
      payerSuggestion: PayerSuggestion.fromValue(map['payerSuggestion']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'title': title,
        'description': description,
        'placeType': placeType,
        'payerSuggestion': payerSuggestion.wireName,
      };
}

/// Resultado emitido por la IA al terminar el reto (formato estable).
class ChatGameResult {
  const ChatGameResult({
    this.winnerUserId,
    this.isDraw = false,
    this.chemistryScore = 0,
    this.bestMoment = '',
    this.reason = '',
    this.suggestedDatePlan,
    this.followUpMessage = '',
    this.noWinner = false,
  });

  /// Ganador (null si empate o sin ganador).
  final String? winnerUserId;
  final bool isDraw;

  /// 0-100. Nivel de "química" estimado por la conversación.
  final int chemistryScore;

  /// Mejor frase/momento del reto.
  final String bestMoment;

  /// Por qué ese resultado (tono amable, nunca físico ni ofensivo).
  final String reason;

  final SuggestedDatePlan? suggestedDatePlan;

  /// Mensaje para seguir la conversación.
  final String followUpMessage;

  /// True si no hubo mensajes suficientes para decidir (propone seguir).
  final bool noWinner;

  factory ChatGameResult.fromMap(Map<String, dynamic> map) {
    final Object? plan = map['suggestedDatePlan'];
    return ChatGameResult(
      winnerUserId: (map['winnerUserId'] as String?)?.trim().isNotEmpty == true
          ? map['winnerUserId'] as String
          : null,
      isDraw: map['isDraw'] == true,
      chemistryScore: _asInt(map['chemistryScore']),
      bestMoment: (map['bestMoment'] as String?) ?? '',
      reason: (map['reason'] as String?) ?? '',
      suggestedDatePlan: plan is Map
          ? SuggestedDatePlan.fromMap(
              plan.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          : null,
      followUpMessage: (map['followUpMessage'] as String?) ?? '',
      noWinner: map['noWinner'] == true,
    );
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// Sesión completa del reto. Inmutable; se reconstruye del doc de Firestore.
class ChatGameSession {
  const ChatGameSession({
    required this.id,
    required this.chatId,
    required this.matchId,
    required this.creatorUserId,
    required this.invitedUserId,
    required this.status,
    required this.mode,
    this.acceptedBy = const <String>[],
    this.themeId = '',
    this.themeTitle = '',
    this.themeCategory = '',
    this.startedAt,
    this.endsAt,
    this.completedAt,
    this.createdAt,
    this.result,
  });

  final String id;
  final String chatId;
  final String matchId;
  final String creatorUserId;
  final String invitedUserId;
  final ChatGameStatus status;
  final ChatGameMode mode;
  final List<String> acceptedBy;

  /// Tema/reto generado (del catálogo curado).
  final String themeId;
  final String themeTitle;
  final String themeCategory;

  final DateTime? startedAt;
  final DateTime? endsAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  final ChatGameResult? result;

  bool acceptedByBoth() =>
      acceptedBy.contains(creatorUserId) && acceptedBy.contains(invitedUserId);

  bool hasAccepted(String uid) => acceptedBy.contains(uid);

  String otherUid(String uid) =>
      uid == creatorUserId ? invitedUserId : creatorUserId;

  /// Segundos restantes del reto (>=0). 0 si no está activo o ya venció.
  int secondsLeft({DateTime? now}) {
    final DateTime? end = endsAt;
    if (!status.isActive || end == null) return 0;
    final int s = end.difference(now ?? DateTime.now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  factory ChatGameSession.fromMap(String id, Map<String, dynamic> map) {
    return ChatGameSession(
      id: id,
      chatId: (map['chatId'] as String?) ?? '',
      matchId: (map['matchId'] as String?) ?? '',
      creatorUserId: (map['creatorUserId'] as String?) ?? '',
      invitedUserId: (map['invitedUserId'] as String?) ?? '',
      status: ChatGameStatus.fromValue(map['status']),
      mode: ChatGameMode.fromValue(map['mode']),
      acceptedBy: ((map['acceptedBy'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      themeId: (map['themeId'] as String?) ?? '',
      themeTitle: (map['themeTitle'] as String?) ?? '',
      themeCategory: (map['themeCategory'] as String?) ?? '',
      startedAt: _asDate(map['startedAt']),
      endsAt: _asDate(map['endsAt']),
      completedAt: _asDate(map['completedAt']),
      createdAt: _asDate(map['createdAt']),
      result: map['result'] is Map
          ? ChatGameResult.fromMap((map['result'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
          : null,
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
