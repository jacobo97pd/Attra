import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de alerta SafeDate.
enum SafeDateAlertType {
  contactMe('contact_me'),
  callMe('call_me'),
  needExit('need_exit'),
  silentAlert('silent_alert'),
  emergency('emergency'),
  missedCheckin('missed_checkin');

  const SafeDateAlertType(this.wireName);
  final String wireName;

  /// Las silenciosas NO muestran confirmaciones llamativas ni informan al match.
  bool get isSilent =>
      this == SafeDateAlertType.silentAlert ||
      this == SafeDateAlertType.emergency;

  static SafeDateAlertType fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final SafeDateAlertType t in SafeDateAlertType.values) {
      if (t.wireName == raw || t.name.toLowerCase() == raw) return t;
    }
    return SafeDateAlertType.contactMe;
  }
}

/// Severidad (para priorizar moderación/retención, no para acusar).
enum SafeDateAlertSeverity {
  info('info'),
  warning('warning'),
  urgent('urgent');

  const SafeDateAlertSeverity(this.wireName);
  final String wireName;

  static SafeDateAlertSeverity fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final SafeDateAlertSeverity s in SafeDateAlertSeverity.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return SafeDateAlertSeverity.info;
  }
}

/// Alerta (`safeDatePlans/{planId}/alerts/{id}`). Nunca informa al match.
class SafeDateAlert {
  const SafeDateAlert({
    required this.id,
    required this.safeDatePlanId,
    required this.userId,
    required this.alertType,
    required this.severity,
    this.createdAt,
    this.resolvedAt,
    this.metadata,
  });

  final String id;
  final String safeDatePlanId;
  final String userId;
  final SafeDateAlertType alertType;
  final SafeDateAlertSeverity severity;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic>? metadata;

  bool get isResolved => resolvedAt != null;

  factory SafeDateAlert.fromMap(String id, Map<String, dynamic> map) {
    return SafeDateAlert(
      id: id,
      safeDatePlanId: (map['safeDatePlanId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      alertType: SafeDateAlertType.fromValue(map['alertType']),
      severity: SafeDateAlertSeverity.fromValue(map['severity']),
      createdAt: _asDate(map['createdAt']),
      resolvedAt: _asDate(map['resolvedAt']),
      metadata: map['metadata'] is Map
          ? (map['metadata'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
          : null,
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
