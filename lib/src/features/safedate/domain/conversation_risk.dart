/// Resultado de la revisión preventiva de una conversación. NO contiene el
/// texto de los mensajes (el backend no lo persiste ni lo devuelve): solo un
/// nivel orientativo, categorías detectadas y consejos suaves. Nunca es un
/// veredicto sobre la persona.
class ConversationRiskResult {
  const ConversationRiskResult({
    required this.tier,
    required this.categories,
    required this.intro,
    required this.tips,
  });

  /// info | warning | urgent (orientativo, no acusatorio).
  final String tier;
  final List<String> categories;
  final String intro;
  final List<String> tips;

  bool get hasSignals => tier != 'info' && tips.isNotEmpty;

  factory ConversationRiskResult.fromMap(Map<String, dynamic> map) {
    List<String> list(Object? v) => v is List
        ? v.map((Object? e) => e.toString()).toList(growable: false)
        : const <String>[];
    return ConversationRiskResult(
      tier: (map['tier'] ?? 'info').toString(),
      categories: list(map['categories']),
      intro: (map['intro'] ?? '').toString(),
      tips: list(map['tips']),
    );
  }
}
