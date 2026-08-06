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
    this.datePlansEnabled = false,
    this.datePlansAiEnabled = false,
    this.datePlansPlacesEnabled = false,
    this.datePlansAutoNudgeEnabled = false,
    this.datePlansKillSwitch = false,
    this.datePlansFreeLimit = 1,
    this.adsEnabled = false,
    this.weeklyFreeAttras = 0,
    this.freeMonthlyAttras = 1,
    this.plusMonthlyAttras = 5,
    this.premiumMonthlyAttras = 10,
    this.proMonthlyAttras = 15,
    this.freeMonthlyBoosts = 0,
    this.plusMonthlyBoosts = 1,
    this.premiumMonthlyBoosts = 2,
    this.proMonthlyBoosts = 4,
    this.superboostCostBoosts = 3,
    this.freeDailyLikes = 25,
    this.plusDailyLikes = 100,
    this.rawConfig = const <String, dynamic>{},
  });

  /// Doc crudo `config/featureFlags` (para módulos que leen claves propias, p.ej.
  /// el ranking lee `ranking_*` vía RankingConfig.fromMap). No se usa para los
  /// flags tipados de arriba.
  final Map<String, dynamic> rawConfig;

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
        datePlansEnabled = false,
        datePlansAiEnabled = false,
        datePlansPlacesEnabled = false,
        datePlansAutoNudgeEnabled = false,
        datePlansKillSwitch = true,
        datePlansFreeLimit = 0,
        adsEnabled = false,
        weeklyFreeAttras = 0,
        freeMonthlyAttras = 0,
        plusMonthlyAttras = 0,
        premiumMonthlyAttras = 0,
        proMonthlyAttras = 0,
        freeMonthlyBoosts = 0,
        plusMonthlyBoosts = 0,
        premiumMonthlyBoosts = 0,
        proMonthlyBoosts = 0,
        // OJO: el coste del Superboost NO se pone a 0 con la monetización
        // apagada. Un coste 0 regalaría Superboosts en vez de bloquearlos, que
        // es justo lo contrario de lo que quiere un kill switch.
        superboostCostBoosts = 3,
        // Los topes de likes tampoco se ponen a 0: apagar la monetización no
        // puede dejar a la gente sin poder dar likes. Se quedan en los mismos
        // números que en el constructor normal.
        freeDailyLikes = 25,
        plusDailyLikes = 100,
        rawConfig = const <String, dynamic>{};

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

  /// Attra Plans: propuestas de cita con opciones reales (Places) + votación.
  /// Todos OPT-IN (default false). `datePlansKillSwitch` apaga TODA la feature
  /// en caliente aunque `datePlansEnabled` esté true.
  final bool datePlansEnabled;
  final bool datePlansAiEnabled;
  final bool datePlansPlacesEnabled;
  final bool datePlansAutoNudgeEnabled;
  final bool datePlansKillSwitch;

  /// Propuestas IA gratis por match para usuarios Free (Plus/Pro amplían).
  final int datePlansFreeLimit;

  /// Anuncios (AdMob native cards en el feed). OPT-IN, default false. Aunque
  /// esté true, NO se muestran a Plus/Pro (se decide en la UI con el tier).
  final bool adsEnabled;

  final int weeklyFreeAttras;

  /// Attras incluidos cada mes por tier. `freeMonthlyAttras` es NUEVO: Free
  /// recibía 0, así que nadie probaba nunca un Attra y no había gancho de
  /// conversión. 1 al mes es el "prueba de verdad" del plan Free.
  final int freeMonthlyAttras;
  final int plusMonthlyAttras;
  final int premiumMonthlyAttras;
  final int proMonthlyAttras;

  /// Boosts incluidos cada mes por tier. Antes NO existía ningún grant: la
  /// feature `monthlyBoost` se anunciaba en el paywall pero no regalaba nada.
  /// Hay una sola moneda de Boost, así que estos números son lo que el usuario
  /// puede repartir entre Boost normal (1) y Superboost ([superboostCostBoosts]).
  final int freeMonthlyBoosts;
  final int plusMonthlyBoosts;
  final int premiumMonthlyBoosts;
  final int proMonthlyBoosts;

  /// Cuántos Boosts del saldo cuesta un Superboost (24 h, +150 de prioridad).
  /// Antes costaba 1, exactamente lo mismo que el Boost de 30 min (+80): el
  /// producto caro salía gratis. Con 3, el saldo mensual se puede expresar en
  /// una sola unidad y el usuario decide cómo gastarlo.
  final int superboostCostBoosts;

  /// Topes de likes diarios. `plusDailyLikes` es NUEVO como flag: el tope solo
  /// existía para Free, así que Plus tenía likes ilimitados de facto y no se
  /// distinguía de Pro. -1 (ilimitado) se reserva a Premium/Pro, ver
  /// [dailyLikesForTier].
  final int freeDailyLikes;
  final int plusDailyLikes;

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

    // Clamp a >= 1: un coste 0 (o negativo) mal configurado en remoto
    // convertiría el Superboost en gratis e infinito. Nunca baja de 1.
    final int rawSuperboostCost =
        readInt('superboost_cost_boosts', readInt('superboostCostBoosts', 3));
    final int superboostCost = rawSuperboostCost < 1 ? 1 : rawSuperboostCost;

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
      datePlansEnabled:
          readBool('date_plans_enabled', readBool('datePlansEnabled', false)),
      datePlansAiEnabled: readBool(
          'date_plans_ai_enabled', readBool('datePlansAiEnabled', false)),
      datePlansPlacesEnabled: readBool('date_plans_places_enabled',
          readBool('datePlansPlacesEnabled', false)),
      datePlansAutoNudgeEnabled: readBool('date_plans_auto_nudge_enabled',
          readBool('datePlansAutoNudgeEnabled', false)),
      datePlansKillSwitch: readBool(
          'date_plans_kill_switch', readBool('datePlansKillSwitch', false)),
      datePlansFreeLimit:
          readInt('date_plans_free_limit', readInt('datePlansFreeLimit', 1)),
      adsEnabled: readBool('ads_enabled', readBool('adsEnabled', false)),
      weeklyFreeAttras: readInt('weeklyFreeAttras', 0),
      // Igual que el resto de flags nuevos: se acepta snake_case (lo que
      // escribe la consola/seed remoto) y camelCase (lo que ya había en
      // `config/featureFlags`). Snake gana si están los dos.
      freeMonthlyAttras:
          readInt('free_monthly_attras', readInt('freeMonthlyAttras', 1)),
      plusMonthlyAttras:
          readInt('plus_monthly_attras', readInt('plusMonthlyAttras', 5)),
      premiumMonthlyAttras: readInt(
          'premium_monthly_attras', readInt('premiumMonthlyAttras', 10)),
      proMonthlyAttras:
          readInt('pro_monthly_attras', readInt('proMonthlyAttras', 15)),
      freeMonthlyBoosts:
          readInt('free_monthly_boosts', readInt('freeMonthlyBoosts', 0)),
      plusMonthlyBoosts:
          readInt('plus_monthly_boosts', readInt('plusMonthlyBoosts', 1)),
      premiumMonthlyBoosts:
          readInt('premium_monthly_boosts', readInt('premiumMonthlyBoosts', 2)),
      proMonthlyBoosts:
          readInt('pro_monthly_boosts', readInt('proMonthlyBoosts', 4)),
      superboostCostBoosts: superboostCost,
      freeDailyLikes:
          readInt('free_daily_likes', readInt('freeDailyLikes', 25)),
      plusDailyLikes:
          readInt('plus_daily_likes', readInt('plusDailyLikes', 100)),
      rawConfig: map,
    );
  }

  /// Attra Plans operativo: activado y sin kill switch. La UI y las funciones
  /// deben comprobar esto antes de mostrar/generar planes.
  bool get datePlansActive => datePlansEnabled && !datePlansKillSwitch;

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

  /// Attras incluidos al mes según el tier. Free ya NO devuelve 0 fijo: recibe
  /// [freeMonthlyAttras] (1 por defecto) para que pueda probar el producto.
  /// Sigue respetando `attrasEnabled` como kill switch de toda la moneda.
  int monthlyAttrasForTier(SubscriptionTier tier) {
    if (!attrasEnabled) {
      return 0;
    }
    switch (tier) {
      case SubscriptionTier.free:
        return freeMonthlyAttras;
      case SubscriptionTier.plus:
        return plusMonthlyAttras;
      case SubscriptionTier.premium:
        return premiumMonthlyAttras;
      case SubscriptionTier.pro:
        return proMonthlyAttras;
    }
  }

  /// Boosts incluidos al mes según el tier (moneda única: el usuario decide si
  /// los gasta en Boosts de 30 min o los junta para un Superboost).
  ///
  /// Se apaga con `monetizationEnabled` porque un grant recurrente es parte de
  /// la suscripción; con la monetización off nadie debería estar acumulando
  /// saldo de un plan que no se está cobrando.
  int monthlyBoostsForTier(SubscriptionTier tier) {
    if (!monetizationEnabled) {
      return 0;
    }
    switch (tier) {
      case SubscriptionTier.free:
        return freeMonthlyBoosts;
      case SubscriptionTier.plus:
        return plusMonthlyBoosts;
      case SubscriptionTier.premium:
        return premiumMonthlyBoosts;
      case SubscriptionTier.pro:
        return proMonthlyBoosts;
    }
  }

  /// Tope de likes diarios por tier. -1 = ilimitado.
  ///
  /// Existe para que el número deje de estar hardcodeado en el controlador y
  /// se pueda mover en caliente desde `config/featureFlags` sin publicar app.
  /// Premium/Pro son ilimitados (es la ventaja de alcance que los diferencia
  /// de Plus, que se queda en [plusDailyLikes]).
  int dailyLikesForTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return freeDailyLikes;
      case SubscriptionTier.plus:
        return plusDailyLikes;
      case SubscriptionTier.premium:
      case SubscriptionTier.pro:
        return -1;
    }
  }
}
