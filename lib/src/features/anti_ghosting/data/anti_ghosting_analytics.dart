import '../../feed/data/feed_metrics_service.dart';

/// Eventos de analytics de Attra Clear (§11). Envuelve [FeedMetricsService]
/// (que respeta el consentimiento de analítica → §12) y **nunca** incluye
/// contenido de mensajes. Si no hay servicio (null), es no-op silencioso.
class AntiGhostingAnalytics {
  const AntiGhostingAnalytics({required this.uid, this.metrics});

  final String uid;
  final FeedMetricsService? metrics;

  // Nombres de evento (única fuente de verdad, §11).
  static const String nudgeShown = 'anti_ghosting_nudge_shown';
  static const String nudgeAction = 'anti_ghosting_nudge_action';
  static const String closedRespectfully = 'conversation_closed_respectfully';
  static const String closeCancelled = 'conversation_close_cancelled';
  static const String pendingLimitReached = 'pending_reply_limit_reached';
  static const String pendingLimitCtaClicked = 'pending_reply_limit_cta_clicked';
  static const String busyModeEnabled = 'busy_mode_enabled';
  static const String busyModeDisabled = 'busy_mode_disabled';
  static const String dateFollowupShown = 'date_followup_shown';
  static const String dateFollowupAnswered = 'date_followup_answered';
  static const String lastAttemptSuggested = 'last_attempt_suggested';
  static const String archivedAfterInactivity =
      'conversation_archived_after_inactivity';
  static const String reliabilityBadgeShown = 'reliability_badge_shown';
  static const String reliabilityScoreUpdated = 'reliability_score_updated';

  void _log(String event, Map<String, dynamic> params) {
    metrics?.log(event, uid: uid, meta: params);
  }

  void logPendingLimitReached({
    required int pendingCount,
    required String userPlan,
    String sourceScreen = 'feed',
  }) {
    _log(pendingLimitReached, <String, dynamic>{
      'pending_count': pendingCount,
      'user_plan': userPlan,
      'source_screen': sourceScreen,
    });
  }

  void logPendingLimitCta({
    required String action,
    required int pendingCount,
    required String userPlan,
  }) {
    _log(pendingLimitCtaClicked, <String, dynamic>{
      'action': action,
      'pending_count': pendingCount,
      'user_plan': userPlan,
    });
  }

  void logBusyModeEnabled({required int durationDays, String userPlan = ''}) {
    _log(busyModeEnabled, <String, dynamic>{
      'duration_days': durationDays,
      if (userPlan.isNotEmpty) 'user_plan': userPlan,
    });
  }

  void logBusyModeDisabled() => _log(busyModeDisabled, <String, dynamic>{});

  void logNudgeShown({required String tier, int? hoursWaiting}) {
    _log(nudgeShown, <String, dynamic>{
      'tier': tier,
      if (hoursWaiting != null) 'hours_waiting': hoursWaiting,
      'source_screen': 'chat',
    });
  }

  void logNudgeAction({required String tier, required String action}) {
    _log(nudgeAction, <String, dynamic>{
      'tier': tier,
      'action': action,
      'source_screen': 'chat',
    });
  }

  void logClosedRespectfully({String? reason, int? hoursWaiting}) {
    _log(closedRespectfully, <String, dynamic>{
      if (reason != null) 'reason': reason,
      if (hoursWaiting != null) 'hours_waiting': hoursWaiting,
    });
  }

  void logCloseCancelled() => _log(closeCancelled, <String, dynamic>{});
}
