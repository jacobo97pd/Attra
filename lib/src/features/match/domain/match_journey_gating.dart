import '../../monetization/domain/subscription_tier.dart';

/// Límites del Match Journey por tier (Fase 10). CONFIGURABLE con defaults
/// seguros. NO conecta compras nuevas: solo decide qué se ofrece según el
/// entitlement REAL del usuario. Si monetización aún no está cerrada, los
/// gates de pago quedan desactivados de forma segura (no se desbloquea Pro sin
/// entitlement real).
class JourneyLimits {
  const JourneyLimits({
    required this.dailyIcebreakers,
    required this.dailyMinigames,
    required this.dateBuilderFull,
    required this.canReactivate,
    required this.aiCoach,
  });

  /// Icebreakers que puede lanzar al día (gate suave; -1 = sin límite).
  final int dailyIcebreakers;

  /// Minijuegos que puede iniciar al día (-1 = sin límite).
  final int dailyMinigames;

  /// Date Builder con TODAS las opciones (Free puede tener una versión básica).
  final bool dateBuilderFull;

  /// Puede reactivar matches enfriados.
  final bool canReactivate;

  /// IA coach conversacional (Pro). NUNCA responde por el usuario: solo sugiere.
  final bool aiCoach;

  bool get unlimitedIcebreakers => dailyIcebreakers < 0;
  bool get unlimitedMinigames => dailyMinigames < 0;

  JourneyLimits copyWith({
    int? dailyIcebreakers,
    int? dailyMinigames,
    bool? dateBuilderFull,
    bool? canReactivate,
    bool? aiCoach,
  }) {
    return JourneyLimits(
      dailyIcebreakers: dailyIcebreakers ?? this.dailyIcebreakers,
      dailyMinigames: dailyMinigames ?? this.dailyMinigames,
      dateBuilderFull: dateBuilderFull ?? this.dateBuilderFull,
      canReactivate: canReactivate ?? this.canReactivate,
      aiCoach: aiCoach ?? this.aiCoach,
    );
  }
}

class MatchJourneyPolicy {
  const MatchJourneyPolicy._();

  /// Defaults SEGUROS (no agresivos). Tunables sin tocar la lógica.
  static const JourneyLimits free = JourneyLimits(
    dailyIcebreakers: 2,
    dailyMinigames: 1,
    dateBuilderFull: false,
    canReactivate: false,
    aiCoach: false,
  );

  static const JourneyLimits plus = JourneyLimits(
    dailyIcebreakers: 10,
    dailyMinigames: 5,
    dateBuilderFull: true,
    canReactivate: true,
    aiCoach: false,
  );

  static const JourneyLimits pro = JourneyLimits(
    dailyIcebreakers: -1,
    dailyMinigames: -1,
    dateBuilderFull: true,
    canReactivate: true,
    aiCoach: true,
  );

  /// Límites para un tier. premium se trata como plus (mismas ventajas sociales).
  static JourneyLimits forTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return free;
      case SubscriptionTier.plus:
      case SubscriptionTier.premium:
        return plus;
      case SubscriptionTier.pro:
        return pro;
    }
  }

  /// Permite sobreescribir los límites desde config remota (futuro), manteniendo
  /// los defaults seguros si la clave no viene.
  static JourneyLimits forTierWithOverrides(
    SubscriptionTier tier,
    Map<String, dynamic>? config,
  ) {
    final JourneyLimits base = forTier(tier);
    if (config == null || config.isEmpty) return base;
    int readInt(String k, int fallback) {
      final Object? v = config[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }

    bool readBool(String k, bool fallback) =>
        config[k] is bool ? config[k] as bool : fallback;

    return base.copyWith(
      dailyIcebreakers: readInt('dailyIcebreakers', base.dailyIcebreakers),
      dailyMinigames: readInt('dailyMinigames', base.dailyMinigames),
      dateBuilderFull: readBool('dateBuilderFull', base.dateBuilderFull),
      canReactivate: readBool('canReactivate', base.canReactivate),
      aiCoach: readBool('aiCoach', base.aiCoach),
    );
  }
}
