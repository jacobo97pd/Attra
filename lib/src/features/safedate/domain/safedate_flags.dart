// Attra SafeDate — configuración remota (Remote Config vía
// `config/featureFlags` → `MonetizationFeatureFlags.rawConfig`). Sigue el patrón
// de RankingConfig/AntiGhostingConfig: claves `feature_safedate_*` con DEFAULTS
// LOCALES SEGUROS (todo OFF) si Remote Config no carga o el doc no existe.
//
// Regla de oro: si algo falla, SafeDate queda DESACTIVADO. Nunca una función de
// ubicación activa sin confirmación del usuario.

class SafeDateFlags {
  const SafeDateFlags({
    this.enabled = false,
    this.trustedContactsEnabled = false,
    this.datePlanEnabled = false,
    this.checkinsEnabled = false,
    this.liveLocationEnabled = false,
    this.discreetAlertEnabled = false,
    this.postDateReviewEnabled = false,
    this.aiRiskDetectionEnabled = false,
    this.verifiedOnlyFilterEnabled = false,
    this.safePlacesEnabled = false,
    // Tiempos de check-in (minutos), configurables desde Remote Config.
    this.checkinFirstReminderMinutes = 10,
    this.checkinSecondReminderMinutes = 10,
    this.checkinMissedThresholdMinutes = 25,
    // Número de emergencia por país (ampliable). España: 112.
    this.emergencyNumber = '112',
  });

  /// Master switch. Si `false`, SafeDate no aparece y la app va EXACTAMENTE
  /// como antes.
  final bool enabled;

  final bool trustedContactsEnabled;
  final bool datePlanEnabled;
  final bool checkinsEnabled;
  final bool liveLocationEnabled;
  final bool discreetAlertEnabled;
  final bool postDateReviewEnabled;
  final bool aiRiskDetectionEnabled;
  final bool verifiedOnlyFilterEnabled;
  final bool safePlacesEnabled;

  final int checkinFirstReminderMinutes;
  final int checkinSecondReminderMinutes;
  final int checkinMissedThresholdMinutes;
  final String emergencyNumber;

  /// Un sub-feature está operativo solo si el master switch está ON y su propia
  /// flag también. Así apagar `enabled` desactiva SafeDate entero de golpe.
  bool get contactsActive => enabled && trustedContactsEnabled;
  bool get datePlanActive => enabled && datePlanEnabled;
  bool get checkinsActive => enabled && checkinsEnabled;
  bool get liveLocationActive => enabled && liveLocationEnabled;
  bool get discreetAlertActive => enabled && discreetAlertEnabled;
  bool get postDateReviewActive => enabled && postDateReviewEnabled;
  bool get aiRiskActive => enabled && aiRiskDetectionEnabled;
  bool get verifiedOnlyFilterActive => enabled && verifiedOnlyFilterEnabled;
  bool get safePlacesActive => enabled && safePlacesEnabled;

  factory SafeDateFlags.fromMap(Map<String, dynamic> map) {
    bool b(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    int i(String key, int fallback) {
      final Object? v = map[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return SafeDateFlags(
      enabled: b('feature_safedate_enabled', false),
      trustedContactsEnabled:
          b('feature_safedate_trusted_contacts_enabled', false),
      datePlanEnabled: b('feature_safedate_date_plan_enabled', false),
      checkinsEnabled: b('feature_safedate_checkins_enabled', false),
      liveLocationEnabled: b('feature_safedate_live_location_enabled', false),
      discreetAlertEnabled: b('feature_safedate_discreet_alert_enabled', false),
      postDateReviewEnabled:
          b('feature_safedate_post_date_review_enabled', false),
      aiRiskDetectionEnabled:
          b('feature_safedate_ai_risk_detection_enabled', false),
      verifiedOnlyFilterEnabled:
          b('feature_safedate_verified_only_filter_enabled', false),
      safePlacesEnabled: b('feature_safedate_safe_places_enabled', false),
      checkinFirstReminderMinutes:
          i('safedate_checkin_first_reminder_minutes', 10),
      checkinSecondReminderMinutes:
          i('safedate_checkin_second_reminder_minutes', 10),
      checkinMissedThresholdMinutes:
          i('safedate_checkin_missed_threshold_minutes', 25),
      emergencyNumber: (map['safedate_emergency_number'] as String?) ?? '112',
    );
  }

  /// Fallback seguro (todo OFF) si Remote Config no está disponible.
  static const SafeDateFlags disabled = SafeDateFlags();
}
