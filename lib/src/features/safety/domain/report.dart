import 'package:cloud_firestore/cloud_firestore.dart';

/// Motivo del reporte. Lista no sensible y ampliable.
enum ReportReason {
  inappropriate('inappropriate'),
  harassment('harassment'),
  spam('spam'),
  fakeProfile('fake_profile'),
  underage('underage'),
  other('other');

  const ReportReason(this.wireName);

  final String wireName;

  String get label {
    switch (this) {
      case ReportReason.inappropriate:
        return 'Contenido inapropiado';
      case ReportReason.harassment:
        return 'Acoso o abuso';
      case ReportReason.spam:
        return 'Spam o estafa';
      case ReportReason.fakeProfile:
        return 'Perfil falso';
      case ReportReason.underage:
        return 'Parece menor de edad';
      case ReportReason.other:
        return 'Otro';
    }
  }

  static ReportReason fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final ReportReason reason in ReportReason.values) {
      if (reason.wireName == raw || reason.name == raw) {
        return reason;
      }
    }
    return ReportReason.other;
  }
}

/// Estado de moderacion del reporte (lo gestiona trust & safety / backend).
enum ReportStatus {
  pending('pending'),
  reviewed('reviewed'),
  actioned('actioned'),
  dismissed('dismissed');

  const ReportStatus(this.wireName);

  final String wireName;

  static ReportStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final ReportStatus status in ReportStatus.values) {
      if (status.wireName == raw || status.name == raw) {
        return status;
      }
    }
    return ReportStatus.pending;
  }
}

/// Reporte de un usuario sobre otro (opcionalmente sobre un mensaje concreto).
/// No se borran evidencias necesarias para moderacion.
class Report {
  const Report({
    required this.id,
    required this.reporterUid,
    required this.reportedUid,
    required this.reason,
    required this.status,
    this.details = '',
    this.matchId,
    this.chatId,
    this.messageId,
    this.createdAt,
  });

  final String id;
  final String reporterUid;
  final String reportedUid;
  final ReportReason reason;
  final ReportStatus status;
  final String details;
  final String? matchId;
  final String? chatId;
  final String? messageId;
  final DateTime? createdAt;

  factory Report.fromMap(String id, Map<String, dynamic> map) {
    return Report(
      id: id,
      reporterUid: (map['reporterUid'] as String?) ?? '',
      reportedUid: (map['reportedUid'] as String?) ?? '',
      reason: ReportReason.fromValue(map['reason']),
      status: ReportStatus.fromValue(map['status']),
      details: (map['details'] as String?) ?? '',
      matchId: map['matchId'] as String?,
      chatId: map['chatId'] as String?,
      messageId: map['messageId'] as String?,
      createdAt: _asDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'reporterUid': reporterUid,
      'reportedUid': reportedUid,
      'reason': reason.wireName,
      'status': ReportStatus.pending.wireName,
      'details': details,
      if (matchId != null) 'matchId': matchId,
      if (chatId != null) 'chatId': chatId,
      if (messageId != null) 'messageId': messageId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
