import 'premium_feature.dart';
import 'subscription_tier.dart';

class MonetizationFeatureFlags {
  const MonetizationFeatureFlags({
    this.monetizationEnabled = true,
    this.attrasEnabled = true,
    this.plusEnabled = true,
    this.premiumEnabled = true,
    this.proAiEnabled = true,
    this.visualSearchEnabled = true,
    this.visualTraitFiltersEnabled = true,
    this.aiProcessingEnabled = true,
    this.aiKillSwitch = false,
    this.sparkEnabled = false,
    this.matchJourneyEnabled = false,
    this.icebreakersEnabled = false,
    this.miniGamesEnabled = false,
    this.doubleAnswerEnabled = false,
    this.thisOrThatEnabled = false,
    this.twoTruthsEnabled = false,
    this.chatGameEnabled = false,
    this.dateBuilderEnabled = false,
    this.matchReactivationEnabled = false,
    this.adsEnabled = false,
    this.weeklyFreeAttras = 0,
    this.plusMonthlyAttras = 3,
    this.premiumMonthlyAttras = 10,
    this.proMonthlyAttras = 15,
  });

  const MonetizationFeatureFlags.disabled()
      : monetizationEnabled = false,
        attrasEnabled = false,
        plusEnabled = false,
        premiumEnabled = false,
        proAiEnabled = false,
        visualSearchEnabled = false,
        visualTraitFiltersEnabled = false,
        aiProcessingEnabled = false,
        aiKillSwitch = true,
        sparkEnabled = false,
        matchJourneyEnabled = false,
        icebreakersEnabled = false,
        miniGamesEnabled = false,
        doubleAnswerEnabled = false,
        thisOrThatEnabled = false,
        twoTruthsEnabled = false,
        chatGameEnabled = false,
        dateBuilderEnabled = false,
        matchReactivationEnabled = false,
        adsEnabled = false,
        weeklyFreeAttras = 0,
        plusMonthlyAttras = 0,
        premiumMonthlyAttras = 0,
        proMonthlyAttras = 0;

  final bool monetizationEnabled;
  final bool attrasEnabled;
  final bool plusEnabled;
  final bool premiumEnabled;
  final bool proAiEnabled;
  final bool visualSearchEnabled;
  final bool visualTraitFiltersEnabled;
  final bool aiProcessingEnabled;
  final bool aiKillSwitch;

  /// Attra Spark (juego de 5 min para romper el hielo tras un match). OPT-IN
  /// por flag remoto: si está desactivado, la app funciona igual que siempre.
  final bool sparkEnabled;

  /// Attra Match Journey: recorrido guiado del match (icebreaker → minijuego →
  /// conversación → plan). Todos OPT-IN (default false) — la app va igual si off.
  final bool matchJourneyEnabled;
  final bool icebreakersEnabled;
  final bool miniGamesEnabled;
  final bool doubleAnswerEnabled;

  /// "Duelo de Química" (reto de 5 min con resultado IA) en el chat.
  final bool chatGameEnabled;
  final bool thisOrThatEnabled;
  final bool twoTruthsEnabled;
  final bool dateBuilderEnabled;
  final bool matchReactivationEnabled;

  /// Anuncios (AdMob native cards en el feed). OPT-IN, default false. Aunque
  /// esté true, NO se muestran a Plus/Pro (se decide en la UI con el tier).
  final bool adsEnabled;

  final int weeklyFreeAttras;
  final int plusMonthlyAttras;
  final int premiumMonthlyAttras;
  final int proMonthlyAttras;

  factory MonetizationFeatureFlags.fromMap(Map<String, dynamic> map) {
    bool readBool(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    int readInt(String key, int fallback) {
      final Object? value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return MonetizationFeatureFlags(
      monetizationEnabled: readBool('monetizationEnabled', true),
      attrasEnabled: readBool('attrasEnabled', true),
      plusEnabled: readBool('plusEnabled', true),
      premiumEnabled: readBool('premiumEnabled', true),
      proAiEnabled: readBool('proAiEnabled', true),
      visualSearchEnabled: readBool('visualSearchEnabled', true),
      visualTraitFiltersEnabled: readBool('visualTraitFiltersEnabled', true),
      aiProcessingEnabled: readBool('aiProcessingEnabled', true),
      aiKillSwitch: readBool('aiKillSwitch', false),
      // Acepta snake_case (spark_enabled) y camelCase (sparkEnabled).
      sparkEnabled: readBool('spark_enabled', readBool('sparkEnabled', false)),
      matchJourneyEnabled: readBool(
          'match_journey_enabled', readBool('matchJourneyEnabled', false)),
      icebreakersEnabled: readBool(
          'icebreakers_enabled', readBool('icebreakersEnabled', false)),
      miniGamesEnabled:
          readBool('mini_games_enabled', readBool('miniGamesEnabled', false)),
      doubleAnswerEnabled: readBool(
          'double_answer_enabled', readBool('doubleAnswerEnabled', false)),
      thisOrThatEnabled: readBool(
          'this_or_that_enabled', readBool('thisOrThatEnabled', false)),
      twoTruthsEnabled:
          readBool('two_truths_enabled', readBool('twoTruthsEnabled', false)),
      chatGameEnabled:
          readBool('chat_game_enabled', readBool('chatGameEnabled', false)),
      dateBuilderEnabled: readBool(
          'date_builder_enabled', readBool('dateBuilderEnabled', false)),
      matchReactivationEnabled: readBool('match_reactivation_enabled',
          readBool('matchReactivationEnabled', false)),
      adsEnabled: readBool('ads_enabled', readBool('adsEnabled', false)),
      weeklyFreeAttras: readInt('weeklyFreeAttras', 0),
      plusMonthlyAttras: readInt('plusMonthlyAttras', 3),
      premiumMonthlyAttras: readInt('premiumMonthlyAttras', 10),
      proMonthlyAttras: readInt('proMonthlyAttras', 15),
    );
  }

  bool isTierEnabled(SubscriptionTier tier) {
    if (!monetizationEnabled && tier.isPaid) {
      return false;
    }
    switch (tier) {
      case SubscriptionTier.free:
        return true;
      case SubscriptionTier.plus:
        return plusEnabled;
      case SubscriptionTier.premium:
        return premiumEnabled;
      case SubscriptionTier.pro:
        return premiumEnabled && proAiEnabled && !aiKillSwitch;
    }
  }

  bool isFeatureEnabled(PremiumFeature feature) {
    if (!monetizationEnabled) {
      return false;
    }
    if (feature == PremiumFeature.attrasMonthlyGrant) {
      return attrasEnabled;
    }
    if (!feature.isAiVisual) {
      return true;
    }
    if (aiKillSwitch || !proAiEnabled || !aiProcessingEnabled) {
      return false;
    }
    if (feature == PremiumFeature.visualReferenceSearch) {
      return visualSearchEnabled;
    }
    if (feature == PremiumFeature.aiVisualTraitFilters) {
      return visualTraitFiltersEnabled;
    }
    return true;
  }

  int monthlyAttrasForTier(SubscriptionTier tier) {
    if (!attrasEnabled) {
      return 0;
    }
    switch (tier) {
      case SubscriptionTier.free:
        return 0;
      case SubscriptionTier.plus:
        return plusMonthlyAttras;
      case SubscriptionTier.premium:
        return premiumMonthlyAttras;
      case SubscriptionTier.pro:
        return proMonthlyAttras;
    }
  }
}
