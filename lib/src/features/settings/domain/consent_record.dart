import 'package:cloud_firestore/cloud_firestore.dart';

/// Una entrada del "consent ledger": registro inmutable de un consentimiento
/// otorgado o retirado, con finalidad, base juridica y fecha. Cada cambio
/// genera una entrada nueva (no se sobrescribe) para poder probar cumplimiento.
class ConsentRecord {
  const ConsentRecord({
    required this.purpose,
    required this.granted,
    required this.legalBasis,
    required this.settingKey,
    required this.recordedAt,
    this.policyVersion,
  });

  final String purpose;
  final bool granted;
  final String legalBasis;
  final String settingKey;
  final DateTime? recordedAt;
  final int? policyVersion;

  factory ConsentRecord.fromMap(Map<String, dynamic> data) {
    final dynamic ts = data['recordedAt'];
    return ConsentRecord(
      purpose: (data['purpose'] as String?) ?? '',
      granted: (data['granted'] as bool?) ?? false,
      legalBasis: (data['legalBasis'] as String?) ?? 'none',
      settingKey: (data['settingKey'] as String?) ?? '',
      recordedAt: ts is Timestamp ? ts.toDate() : null,
      policyVersion: (data['policyVersion'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'purpose': purpose,
        'granted': granted,
        'legalBasis': legalBasis,
        'settingKey': settingKey,
        'policyVersion': policyVersion,
        'recordedAt': FieldValue.serverTimestamp(),
      };
}
