/// Configuración CENTRALIZADA y remotamente configurable del ranking del feed.
///
/// Pesos de la fórmula v1 (heurística, explicable). Se pueden sobreescribir
/// desde `config/featureFlags` (el "Remote Config" del proyecto) sin tocar la
/// lógica. Los 5 scores ORGÁNICOS suman 1.0; la monetización es una capa
/// SEPARADA, pequeña y acotada (BoostAwareRanker), que nunca salta filtros duros.
///
/// PRIVACIDAD: estos scores son server-side/privados. NUNCA se muestran al
/// usuario como "nota"/"nivel". No usan atributos sensibles.
class RankingConfig {
  const RankingConfig({
    this.enabled = true,
    this.wProfileQuality = 0.20,
    this.wReciprocity = 0.35,
    this.wConnection = 0.20,
    this.wTrustSafety = 0.15,
    this.wFreshness = 0.10,
    this.penaltyWeight = 0.30,
    this.maxMonetizationBoost = 0.08,
    this.coldStartBoost = 0.15,
    this.exposureCapPenalty = 0.12,
    this.jitter = 0.03,
    this.diversityInjectionEvery = 7,
  });

  /// Si false, el feed usa el orden base sin scoring avanzado (rollback seguro).
  final bool enabled;

  // --- Pesos de los 5 scores orgánicos (deben sumar ~1) ---
  final double wProfileQuality;
  final double wReciprocity;
  final double wConnection;
  final double wTrustSafety;
  final double wFreshness;

  /// Peso de la penalización (trust&safety negativo). Resta al final.
  final double penaltyWeight;

  /// Tope del boost de pago (Plus/Pro/Attra). Pequeño: nunca supera la
  /// compatibilidad real.
  final double maxMonetizationBoost;

  /// Boost temporal a usuarios nuevos (cold start) mientras dure su ventana.
  final double coldStartBoost;

  /// Penalización por superar el exposure cap (anti "rich get richer").
  final double exposureCapPenalty;

  /// Randomización controlada [±jitter] para que el feed no sea determinista.
  final double jitter;

  /// Cada N posiciones se inyecta diversidad (explora candidatos con potencial).
  final int diversityInjectionEvery;

  /// Suma de pesos orgánicos (para normalizar si la config no suma 1).
  double get organicWeightSum =>
      wProfileQuality + wReciprocity + wConnection + wTrustSafety + wFreshness;

  /// Construye desde el doc de flags (`config/featureFlags`). Claves opcionales:
  /// `ranking_enabled`, `ranking_w_quality`, `ranking_w_reciprocity`,
  /// `ranking_w_connection`, `ranking_w_trust`, `ranking_w_freshness`,
  /// `ranking_max_monetization_boost`, `ranking_cold_start_boost`,
  /// `ranking_exposure_cap_penalty`, `ranking_jitter`. Si falta una, usa el
  /// valor por defecto (no rompe nada).
  factory RankingConfig.fromMap(Map<String, dynamic> map) {
    double d(String key, double fallback) {
      final Object? v = map[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    bool b(String key, bool fallback) {
      final Object? v = map[key];
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return fallback;
    }

    const RankingConfig def = RankingConfig();
    return RankingConfig(
      enabled: b('ranking_enabled', def.enabled),
      wProfileQuality: d('ranking_w_quality', def.wProfileQuality),
      wReciprocity: d('ranking_w_reciprocity', def.wReciprocity),
      wConnection: d('ranking_w_connection', def.wConnection),
      wTrustSafety: d('ranking_w_trust', def.wTrustSafety),
      wFreshness: d('ranking_w_freshness', def.wFreshness),
      maxMonetizationBoost:
          d('ranking_max_monetization_boost', def.maxMonetizationBoost),
      coldStartBoost: d('ranking_cold_start_boost', def.coldStartBoost),
      exposureCapPenalty:
          d('ranking_exposure_cap_penalty', def.exposureCapPenalty),
      jitter: d('ranking_jitter', def.jitter),
    );
  }
}
