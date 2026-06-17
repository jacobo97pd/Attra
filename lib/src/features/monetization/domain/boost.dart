import 'package:cloud_firestore/cloud_firestore.dart';

enum BoostType {
  boostNormal('boost_normal'),
  superboost('superboost');

  const BoostType(this.wireName);

  final String wireName;

  static BoostType fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final BoostType type in BoostType.values) {
      if (type.wireName == raw || type.name.toLowerCase() == raw) {
        return type;
      }
    }
    return BoostType.boostNormal;
  }
}

class ActiveBoost {
  const ActiveBoost({
    required this.boostId,
    required this.userId,
    required this.type,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.priorityBonus,
    required this.impressionCap,
    required this.deliveredImpressions,
  });

  final String boostId;
  final String userId;
  final BoostType type;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int priorityBonus;
  final int impressionCap;
  final int deliveredImpressions;

  bool isActiveAt(DateTime now) {
    final DateTime? expiry = expiresAt;
    if (status != 'active' || expiry == null || !expiry.isAfter(now)) {
      return false;
    }
    return impressionCap <= 0 || deliveredImpressions < impressionCap;
  }

  factory ActiveBoost.fromMap(String fallbackUserId, Map<String, dynamic> map) {
    return ActiveBoost(
      boostId: (map['boostId'] ?? '').toString(),
      userId: (map['userId'] ?? fallbackUserId).toString(),
      type: BoostType.fromValue(map['type']),
      status: (map['status'] ?? 'active').toString(),
      startedAt: _asDate(map['startedAt']),
      expiresAt: _asDate(map['expiresAt']),
      priorityBonus: _asInt(map['priorityBonus']),
      impressionCap: _asInt(map['impressionCap']),
      deliveredImpressions: _asInt(map['deliveredImpressions']),
    );
  }
}

class BoostActivationResult {
  const BoostActivationResult({
    required this.success,
    required this.status,
    required this.remainingBoosts,
    this.boostId,
    this.startedAt,
    this.expiresAt,
  });

  final bool success;
  final String status;
  final int remainingBoosts;
  final String? boostId;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  factory BoostActivationResult.fromMap(Map<String, dynamic> map) {
    return BoostActivationResult(
      success: map['success'] == true,
      status: (map['status'] ?? '').toString(),
      remainingBoosts: _asInt(map['remainingBoosts']),
      boostId: _asNonEmptyString(map['boostId']),
      startedAt: _asDate(map['startedAt']),
      expiresAt: _asDate(map['expiresAt']),
    );
  }
}

class BoostSummary {
  const BoostSummary({
    required this.boostId,
    required this.userId,
    required this.type,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.priorityBonus,
    required this.impressionCap,
    required this.deliveredImpressions,
    required this.profileOpens,
    required this.likesReceived,
    required this.matchesGenerated,
    required this.extendedCount,
  });

  final String boostId;
  final String userId;
  final BoostType type;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int priorityBonus;
  final int impressionCap;
  final int deliveredImpressions;
  final int profileOpens;
  final int likesReceived;
  final int matchesGenerated;
  final int extendedCount;

  factory BoostSummary.fromMap(Map<String, dynamic> map) {
    return BoostSummary(
      boostId: (map['boostId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      type: BoostType.fromValue(map['type']),
      status: (map['status'] ?? '').toString(),
      startedAt: _asDate(map['startedAt']),
      expiresAt: _asDate(map['expiresAt']),
      priorityBonus: _asInt(map['priorityBonus']),
      impressionCap: _asInt(map['impressionCap']),
      deliveredImpressions: _asInt(map['deliveredImpressions']),
      profileOpens: _asInt(map['profileOpens']),
      likesReceived: _asInt(map['likesReceived']),
      matchesGenerated: _asInt(map['matchesGenerated']),
      extendedCount: _asInt(map['extendedCount']),
    );
  }
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _asNonEmptyString(Object? value) {
  final String raw = (value ?? '').toString().trim();
  return raw.isEmpty ? null : raw;
}
