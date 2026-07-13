import 'package:cloud_firestore/cloud_firestore.dart';

/// Categorías de preocupación (para moderación interna; nunca públicas).
class PostDateConcern {
  static const String fakeIdentity = 'fake_identity';
  static const String sexualPressure = 'sexual_pressure';
  static const String insistedAfterNo = 'insisted_after_no';
  static const String aggressive = 'aggressive';
  static const String threats = 'threats';
  static const String controlManipulation = 'control_manipulation';
  static const String isolation = 'isolation';
  static const String substanceIssue = 'substance_issue';
  static const String misleadingLocation = 'misleading_location';
  static const String moneyRequest = 'money_request';
  static const String scam = 'scam';
  static const String other = 'other';

  static const List<String> all = <String>[
    fakeIdentity,
    sexualPressure,
    insistedAfterNo,
    aggressive,
    threats,
    controlManipulation,
    isolation,
    substanceIssue,
    misleadingLocation,
    moneyRequest,
    scam,
    other,
  ];
}

/// Revisión privada posterior a la cita (`safeDateSafetyReviews/{id}`).
/// COMPLETAMENTE privada: no se muestra al evaluado, no hay puntuación pública,
/// no hay rankings. Solo para moderación interna (backend).
class PostDateSafetyReview {
  const PostDateSafetyReview({
    required this.id,
    required this.safeDatePlanId,
    required this.reviewerUserId,
    required this.reviewedUserId,
    required this.feltSafe,
    required this.respectedBoundaries,
    required this.matchedProfile,
    required this.experiencedPressure,
    required this.wantsToBlock,
    required this.wantsToReport,
    this.concernCategories = const <String>[],
    this.encryptedNotes,
    this.createdAt,
  });

  final String id;
  final String safeDatePlanId;
  final String reviewerUserId;
  final String reviewedUserId;
  final bool feltSafe;
  final bool respectedBoundaries;
  final bool matchedProfile;
  final bool experiencedPressure;
  final bool wantsToBlock;
  final bool wantsToReport;
  final List<String> concernCategories;
  final String? encryptedNotes;
  final DateTime? createdAt;

  /// Payload para crear (vía Cloud Function). No incluye notas en claro.
  Map<String, dynamic> toCreateMap() => <String, dynamic>{
        'safeDatePlanId': safeDatePlanId,
        'reviewedUserId': reviewedUserId,
        'feltSafe': feltSafe,
        'respectedBoundaries': respectedBoundaries,
        'matchedProfile': matchedProfile,
        'experiencedPressure': experiencedPressure,
        'wantsToBlock': wantsToBlock,
        'wantsToReport': wantsToReport,
        'concernCategories': concernCategories,
        if (encryptedNotes != null) 'encryptedNotes': encryptedNotes,
      };

  factory PostDateSafetyReview.fromMap(String id, Map<String, dynamic> map) {
    return PostDateSafetyReview(
      id: id,
      safeDatePlanId: (map['safeDatePlanId'] ?? '').toString(),
      reviewerUserId: (map['reviewerUserId'] ?? '').toString(),
      reviewedUserId: (map['reviewedUserId'] ?? '').toString(),
      feltSafe: map['feltSafe'] == true,
      respectedBoundaries: map['respectedBoundaries'] == true,
      matchedProfile: map['matchedProfile'] == true,
      experiencedPressure: map['experiencedPressure'] == true,
      wantsToBlock: map['wantsToBlock'] == true,
      wantsToReport: map['wantsToReport'] == true,
      concernCategories: map['concernCategories'] is List
          ? (map['concernCategories'] as List)
              .map((Object? e) => e.toString())
              .toList()
          : const <String>[],
      encryptedNotes: map['encryptedNotes'] as String?,
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
