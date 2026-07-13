import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado del plan de cita segura.
enum SafeDatePlanStatus {
  draft('draft'),
  scheduled('scheduled'),
  active('active'),
  completed('completed'),
  cancelled('cancelled'),
  alerted('alerted'),
  expired('expired');

  const SafeDatePlanStatus(this.wireName);
  final String wireName;

  bool get isActive => this == SafeDatePlanStatus.active;
  bool get isOpen =>
      this == SafeDatePlanStatus.scheduled || this == SafeDatePlanStatus.active;

  static SafeDatePlanStatus fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final SafeDatePlanStatus s in SafeDatePlanStatus.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return SafeDatePlanStatus.draft;
  }
}

/// Plan de una cita presencial (`safeDatePlans/{planId}`). Backend-autoritativo.
/// Nunca expone datos privados del match. Solo el dueño (ownerUserId) accede.
class SafeDatePlan {
  const SafeDatePlan({
    required this.id,
    required this.ownerUserId,
    required this.matchId,
    required this.otherUserId,
    required this.placeName,
    required this.scheduledAt,
    required this.status,
    this.placeAddress,
    this.latitude,
    this.longitude,
    this.expectedDurationMinutes = 90,
    this.expectedReturnAt,
    this.trustedContactIds = const <String>[],
    this.shareProfileSnapshot = false,
    this.liveLocationEnabled = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String matchId;
  final String otherUserId;
  final String placeName;
  final String? placeAddress;
  final double? latitude;
  final double? longitude;
  final DateTime scheduledAt;
  final int expectedDurationMinutes;
  final DateTime? expectedReturnAt;
  final SafeDatePlanStatus status;
  final List<String> trustedContactIds;
  final bool shareProfileSnapshot;
  final bool liveLocationEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DateTime get effectiveReturnAt =>
      expectedReturnAt ??
      scheduledAt.add(Duration(minutes: expectedDurationMinutes));

  factory SafeDatePlan.fromMap(String id, Map<String, dynamic> map) {
    double? d(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return SafeDatePlan(
      id: id,
      ownerUserId: (map['ownerUserId'] ?? '').toString(),
      matchId: (map['matchId'] ?? '').toString(),
      otherUserId: (map['otherUserId'] ?? '').toString(),
      placeName: (map['placeName'] ?? '').toString(),
      placeAddress: (map['placeAddress'] as String?),
      latitude: d(map['latitude']),
      longitude: d(map['longitude']),
      scheduledAt: _asDate(map['scheduledAt']) ?? DateTime.now(),
      expectedDurationMinutes: map['expectedDurationMinutes'] is num
          ? (map['expectedDurationMinutes'] as num).toInt()
          : 90,
      expectedReturnAt: _asDate(map['expectedReturnAt']),
      status: SafeDatePlanStatus.fromValue(map['status']),
      trustedContactIds: map['trustedContactIds'] is List
          ? (map['trustedContactIds'] as List)
              .map((Object? e) => e.toString())
              .toList()
          : const <String>[],
      shareProfileSnapshot: map['shareProfileSnapshot'] == true,
      liveLocationEnabled: map['liveLocationEnabled'] == true,
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
