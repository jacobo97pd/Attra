import 'intent_mode.dart';

/// Copy dependiente del modo: en amistad/grupos se suaviza el lenguaje
/// romántico (Like→Conectar, Match→Conexión, Cita→Plan, Compatibilidad
/// romántica→Afinidad social). En dating/ambas se mantiene el copy de siempre.
///
/// PURO/testeable. La UI llama `SocialCopy.of(mode)` y usa las etiquetas; no
/// hay strings romperizados por todo el árbol.
class SocialCopy {
  const SocialCopy({
    required this.likeVerb,
    required this.matchNoun,
    required this.dateNoun,
    required this.compatibilityLabel,
    required this.connectCta,
  });

  /// Verbo del "me gusta": "Me gusta" (dating) / "Conectar" (social).
  final String likeVerb;

  /// Sustantivo del match: "Match" / "Conexión".
  final String matchNoun;

  /// Sustantivo del plan/cita: "Cita" / "Plan".
  final String dateNoun;

  /// Etiqueta de compatibilidad: "Compatibilidad" / "Afinidad social".
  final String compatibilityLabel;

  /// CTA principal en la tarjeta: "Dar like" / "Conectar".
  final String connectCta;

  static const SocialCopy romantic = SocialCopy(
    likeVerb: 'Me gusta',
    matchNoun: 'Match',
    dateNoun: 'Cita',
    compatibilityLabel: 'Compatibilidad',
    connectCta: 'Dar like',
  );

  static const SocialCopy social = SocialCopy(
    likeVerb: 'Conectar',
    matchNoun: 'Conexión',
    dateNoun: 'Plan',
    compatibilityLabel: 'Afinidad social',
    connectCta: 'Conectar',
  );

  /// Copy según el modo activo del usuario.
  static SocialCopy of(IntentMode mode) => mode.isSocial ? social : romantic;
}
