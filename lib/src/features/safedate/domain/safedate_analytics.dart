// Attra SafeDate — nombres de eventos de Analytics. NUNCA se envían datos
// sensibles (nombre, teléfono, email, dirección, coordenadas, mensajes, notas de
// reporte, identificadores externos). Solo el nombre del evento y, como mucho,
// valores categóricos/agregados. Ver docs/analytics/SAFEDATE_EVENTS.md.

class SafeDateEvents {
  const SafeDateEvents._();

  static const String opened = 'safedate_opened';
  static const String planStarted = 'safedate_plan_started';
  static const String planCreated = 'safedate_plan_created';
  static const String planCancelled = 'safedate_plan_cancelled';
  static const String planCompleted = 'safedate_plan_completed';
  static const String trustedContactAdded = 'safedate_trusted_contact_added';
  static const String checkinCreated = 'safedate_checkin_created';
  static const String checkinCompleted = 'safedate_checkin_completed';
  static const String checkinMissed = 'safedate_checkin_missed';
  static const String alertTriggered = 'safedate_alert_triggered';
  static const String postReviewCompleted = 'safedate_post_review_completed';
  static const String reportStarted = 'safedate_report_started';
  static const String aiWarningShown = 'safedate_ai_warning_shown';
  static const String aiWarningDismissed = 'safedate_ai_warning_dismissed';
  static const String liveLocationEnabled = 'safedate_live_location_enabled';
  static const String liveLocationDisabled = 'safedate_live_location_disabled';

  /// Campos PROHIBIDOS en parámetros de evento (defensa en código).
  static const Set<String> forbiddenParamKeys = <String>{
    'name',
    'displayName',
    'phone',
    'email',
    'address',
    'lat',
    'latitude',
    'lng',
    'longitude',
    'message',
    'text',
    'notes',
    'reason',
    'externalId',
  };

  /// Filtra parámetros para no enviar nunca datos sensibles.
  static Map<String, Object> safeParams(Map<String, Object> params) {
    return <String, Object>{
      for (final MapEntry<String, Object> e in params.entries)
        if (!forbiddenParamKeys.contains(e.key)) e.key: e.value,
    };
  }
}
