import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de solicitud de privacidad / ciclo de vida de la cuenta.
enum PrivacyRequestType { export, erasure, disable, reactivate }

/// Estado de la solicitud. El cliente la crea como `pending`; el backend
/// (Cloud Function, fuera del alcance de esta tanda) la procesa.
enum PrivacyRequestStatus { pending, processing, ready, completed, rejected }

/// Una solicitud de privacidad: exportacion, borrado o pausa de cuenta.
/// Se modela como peticion (no como ejecucion inmediata) para soportar la
/// "safety retention window" y el procesamiento asincrono que pide el informe.
class PrivacyRequest {
  const PrivacyRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    this.detail = '',
    this.completeBy,
  });

  final String id;
  final PrivacyRequestType type;
  final PrivacyRequestStatus status;
  final DateTime? createdAt;
  final String detail;

  /// Fecha estimada de finalizacion (p.ej. ventana de seguridad de borrado).
  final DateTime? completeBy;

  factory PrivacyRequest.fromMap(String id, Map<String, dynamic> data) {
    final dynamic created = data['createdAt'];
    final dynamic complete = data['completeBy'];
    return PrivacyRequest(
      id: id,
      type: _typeFromString(data['type'] as String?),
      status: _statusFromString(data['status'] as String?),
      createdAt: created is Timestamp ? created.toDate() : null,
      detail: (data['detail'] as String?) ?? '',
      completeBy: complete is Timestamp ? complete.toDate() : null,
    );
  }

  static Map<String, dynamic> newRequestMap({
    required PrivacyRequestType type,
    String detail = '',
    DateTime? completeBy,
  }) {
    return <String, dynamic>{
      'type': type.name,
      'status': PrivacyRequestStatus.pending.name,
      'detail': detail,
      'completeBy': completeBy == null ? null : Timestamp.fromDate(completeBy),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static PrivacyRequestType _typeFromString(String? raw) {
    return PrivacyRequestType.values.firstWhere(
      (PrivacyRequestType t) => t.name == raw,
      orElse: () => PrivacyRequestType.export,
    );
  }

  static PrivacyRequestStatus _statusFromString(String? raw) {
    return PrivacyRequestStatus.values.firstWhere(
      (PrivacyRequestStatus s) => s.name == raw,
      orElse: () => PrivacyRequestStatus.pending,
    );
  }
}
