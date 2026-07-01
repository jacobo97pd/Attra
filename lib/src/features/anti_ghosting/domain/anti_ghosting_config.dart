/// Configuración de **Attra Clear** (sistema anti-ghosting), leída de
/// `config/featureFlags` (el mismo doc remoto que el resto de flags) a través de
/// `MonetizationFeatureFlags.rawConfig`. Sigue el patrón de `RankingConfig`:
/// claves `anti_ghosting_*` con **defaults locales seguros** si Remote Config no
/// carga o el doc no existe.
///
/// Rollout conservador: solo lo NO destructivo (bandeja "Tu turno") viene ON por
/// defecto. Todo lo que bloquea o necesita backend (límite de pendientes,
/// nudges, score, badge…) viene OFF hasta que su fase esté desplegada.
class AntiGhostingConfig {
  const AntiGhostingConfig({
    this.enabled = true,
    this.pendingLimitEnabled = false,
    this.pendingLimitFree = 5,
    this.pendingLimitPlus = 8,
    this.pendingLimitPro = 10,
    this.pendingMaxAgeHours = 24,
    this.softBlockLikesWhenPendingExceeded = true,
    this.softBlockAttrasWhenPendingExceeded = true,
    this.closeGracefullyEnabled = false,
    this.busyModeEnabled = false,
    this.nudgesEnabled = false,
    this.dateFollowupEnabled = false,
    this.reliabilityScoreEnabled = false,
    this.reliabilityBadgeEnabled = false,
    this.breadcrumbingEnabled = false,
  });

  /// Master switch del sistema. Si `false`, la app se comporta EXACTAMENTE como
  /// antes (la bandeja "Tu turno" no aparece y nada se bloquea).
  final bool enabled;

  // --- Límite suave de conversaciones pendientes (sección 2) ---
  final bool pendingLimitEnabled;
  final int pendingLimitFree;
  final int pendingLimitPlus;
  final int pendingLimitPro;
  final int pendingMaxAgeHours;
  final bool softBlockLikesWhenPendingExceeded;
  final bool softBlockAttrasWhenPendingExceeded;

  // --- Resto de fases (gated, default OFF) ---
  final bool closeGracefullyEnabled;
  final bool busyModeEnabled;
  final bool nudgesEnabled;
  final bool dateFollowupEnabled;
  final bool reliabilityScoreEnabled;
  final bool reliabilityBadgeEnabled;
  final bool breadcrumbingEnabled;

  /// Defaults seguros (sistema operativo pero conservador). Útil como fallback.
  static const AntiGhostingConfig safeDefaults = AntiGhostingConfig();

  /// Lee de `rawConfig` (doc `config/featureFlags`). Acepta solo snake_case, que
  /// es la convención del proyecto para claves propias de módulo. Cualquier campo
  /// ausente cae a su default seguro (migración defensiva).
  factory AntiGhostingConfig.fromMap(Map<String, dynamic>? map) {
    final Map<String, dynamic> m = map ?? const <String, dynamic>{};
    bool b(String key, bool fallback) =>
        m[key] is bool ? m[key] as bool : fallback;
    int i(String key, int fallback) {
      final Object? v = m[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    const AntiGhostingConfig d = AntiGhostingConfig.safeDefaults;
    return AntiGhostingConfig(
      enabled: b('anti_ghosting_enabled', d.enabled),
      pendingLimitEnabled:
          b('anti_ghosting_pending_limit_enabled', d.pendingLimitEnabled),
      pendingLimitFree:
          i('anti_ghosting_pending_limit_free', d.pendingLimitFree),
      pendingLimitPlus:
          i('anti_ghosting_pending_limit_plus', d.pendingLimitPlus),
      pendingLimitPro: i('anti_ghosting_pending_limit_pro', d.pendingLimitPro),
      pendingMaxAgeHours:
          i('anti_ghosting_pending_max_age_hours', d.pendingMaxAgeHours),
      softBlockLikesWhenPendingExceeded: b(
          'anti_ghosting_soft_block_likes', d.softBlockLikesWhenPendingExceeded),
      softBlockAttrasWhenPendingExceeded: b('anti_ghosting_soft_block_attras',
          d.softBlockAttrasWhenPendingExceeded),
      closeGracefullyEnabled: b(
          'anti_ghosting_close_gracefully_enabled', d.closeGracefullyEnabled),
      busyModeEnabled:
          b('anti_ghosting_busy_mode_enabled', d.busyModeEnabled),
      nudgesEnabled: b('anti_ghosting_nudges_enabled', d.nudgesEnabled),
      dateFollowupEnabled:
          b('anti_ghosting_date_followup_enabled', d.dateFollowupEnabled),
      reliabilityScoreEnabled: b(
          'anti_ghosting_reliability_score_enabled', d.reliabilityScoreEnabled),
      reliabilityBadgeEnabled: b(
          'anti_ghosting_reliability_badge_enabled', d.reliabilityBadgeEnabled),
      breadcrumbingEnabled:
          b('anti_ghosting_breadcrumbing_enabled', d.breadcrumbingEnabled),
    );
  }

  /// Límite de pendientes según el plan (free/plus/pro). `premium` se trata como
  /// `plus` (mismo margen) salvo que se configure aparte en el futuro.
  int pendingLimitForPlan({required bool isPlus, required bool isPro}) {
    if (isPro) return pendingLimitPro;
    if (isPlus) return pendingLimitPlus;
    return pendingLimitFree;
  }
}
