/// Resultado de una operacion de like/attra devuelto por el backend.
/// El cliente reacciona a esto (mostrar "Nuevo match", paywall, etc.).
enum MatchOutcome {
  liked('liked'),
  matched('matched'),
  alreadyLiked('already_liked'),
  blocked('blocked'),
  limitReached('limit_reached'),
  insufficientAttras('insufficient_attras'),
  error('error');

  const MatchOutcome(this.wireName);

  final String wireName;

  static MatchOutcome fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final MatchOutcome outcome in MatchOutcome.values) {
      if (outcome.wireName == raw || outcome.name == raw) {
        return outcome;
      }
    }
    return MatchOutcome.error;
  }
}

/// Resultado tipado de `sendLike`/`sendAttra`.
class MatchFlowResult {
  const MatchFlowResult({
    required this.outcome,
    this.matchId,
    this.chatId,
    this.message,
  });

  const MatchFlowResult.liked()
      : outcome = MatchOutcome.liked,
        matchId = null,
        chatId = null,
        message = null;

  final MatchOutcome outcome;
  final String? matchId;
  final String? chatId;
  final String? message;

  bool get isMatch => outcome == MatchOutcome.matched;

  factory MatchFlowResult.fromMap(Map<String, dynamic> map) {
    return MatchFlowResult(
      outcome: MatchOutcome.fromValue(map['outcome'] ?? map['result']),
      matchId: map['matchId'] as String?,
      chatId: map['chatId'] as String?,
      message: map['message'] as String?,
    );
  }
}
