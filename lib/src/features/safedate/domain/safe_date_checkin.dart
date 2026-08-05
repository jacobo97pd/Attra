import 'package:cloud_firestore/cloud_firestore.dart';

/// Momento del check-in.
enum CheckInType {
  arrival('arrival'),
  duringDate('during_date'),
  expectedReturn('expected_return'),
  manual('manual');

  const CheckInType(this.wireName);
  final String wireName;

  static CheckInType fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final CheckInType t in CheckInType.values) {
      if (t.wireName == raw || t.name.toLowerCase() == raw) return t;
    }
    return CheckInType.manual;
  }
}

/// Estado del check-in.
enum CheckInStatus {
  pending('pending'),
  ok('ok'),
  remindLater('remind_later'),
  needCall('need_call'),
  needHelp('need_help'),
  missed('missed'),
  cancelled('cancelled'),
  expired('expired');

  const CheckInStatus(this.wireName);
  final String wireName;

  bool get isPending => this == CheckInStatus.pending;
  bool get needsAttention =>
      this == CheckInStatus.needCall ||
      this == CheckInStatus.needHelp ||
      this == CheckInStatus.missed;

  static CheckInStatus fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final CheckInStatus s in CheckInStatus.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return CheckInStatus.pending;
  }
}

/// Check-in de una cita (`safeDatePlans/{planId}/checkIns/{id}`).
class SafeDateCheckIn {
  const SafeDateCheckIn({
    required this.id,
    required this.safeDatePlanId,
    required this.userId,
    required this.type,
    required this.scheduledAt,
    required this.status,
    this.respondedAt,
    this.reminderCount = 0,
    this.createdAt,
  });

  final String id;
  final String safeDatePlanId;
  final String userId;
  final CheckInType type;
  final DateTime scheduledAt;
  final DateTime? respondedAt;
  final CheckInStatus status;
  final int reminderCount;
  final DateTime? createdAt;

  factory SafeDateCheckIn.fromMap(String id, Map<String, dynamic> map) {
    return SafeDateCheckIn(
      id: id,
      // El backend escribe planId/ownerUserId/dueAt; toleramos nombres antiguos.
      safeDatePlanId: (map['planId'] ?? map['safeDatePlanId'] ?? '').toString(),
      userId: (map['ownerUserId'] ?? map['userId'] ?? '').toString(),
      type: CheckInType.fromValue(map['type']),
      scheduledAt: _asDate(map['dueAt']) ??
          _asDate(map['scheduledAt']) ??
          DateTime.now(),
      respondedAt: _asDate(map['respondedAt']),
      status: CheckInStatus.fromValue(map['status']),
      reminderCount: map['reminderCount'] is num
          ? (map['reminderCount'] as num).toInt()
          : 0,
      createdAt: _asDate(map['createdAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
