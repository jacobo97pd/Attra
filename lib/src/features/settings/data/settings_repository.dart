import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/data/user_document_defaults.dart';
import '../domain/consent_record.dart';
import '../domain/privacy_request.dart';
import '../domain/setting_definition.dart';
import '../domain/settings_catalog.dart';

/// Acceso a datos de la Settings Platform sobre Firestore (attra-database).
///
/// Modelo de almacenamiento (decidido con el usuario):
///   users/{uid}.settings            -> mapa plano keyed by setting_key
///   users/{uid}/consentRecords/*    -> ledger inmutable de consentimientos
///   users/{uid}/privacyRequests/*   -> solicitudes export/erasure/disable
///   users/{uid}/auditEvents/*       -> auditoria ligera (lado cliente)
///
/// La validacion de tipos se hace en la app (ver memoria
/// firestore-rules-no-type-validation): las reglas solo controlan ownership y
/// la lista de claves de primer nivel permitidas.
class SettingsRepository {
  SettingsRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Lee el mapa `settings` crudo del documento de usuario.
  Future<Map<String, dynamic>> loadSettings(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _userDoc(uid).get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final dynamic raw = data['settings'];
    if (raw is Map) {
      return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  /// Persiste uno o varios valores de ajuste (deep-merge en `settings`).
  ///
  /// Incluimos `empresa` por defecto para satisfacer la invariante de las
  /// reglas (hasAll(['empresa']) + isRequiredString), igual que UserRepository.
  Future<void> patchValues(String uid, Map<String, Object?> values) async {
    if (values.isEmpty) return;
    await _userDoc(uid).set(
      <String, dynamic>{
        ...UserDocumentDefaults.requiredFields(uid),
        'settings': <String, dynamic>{
          ...values,
          '_schemaVersion': SettingsCatalog.schemaVersion,
          '_updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Anade una entrada al consent ledger (append-only).
  Future<void> recordConsent({
    required String uid,
    required SettingDefinition definition,
    required bool granted,
  }) async {
    final ConsentRecord record = ConsentRecord(
      purpose: definition.consentPurpose ?? definition.key,
      granted: granted,
      legalBasis: definition.legalBasis.name,
      settingKey: definition.key,
      recordedAt: null,
      policyVersion: SettingsCatalog.schemaVersion,
    );
    await _userDoc(uid).collection('consentRecords').add(record.toMap());
  }

  /// Registro de auditoria ligero (lado cliente). El informe pide un audit
  /// completo con ip_hash/correlation_id que es responsabilidad del backend;
  /// aqui guardamos lo accionable para el "historial visible al usuario".
  Future<void> recordAudit({
    required String uid,
    required String event,
    required String settingKey,
    Object? previousValue,
    Object? newValue,
    String reasonCode = 'user_self_service',
  }) async {
    await _userDoc(uid).collection('auditEvents').add(<String, dynamic>{
      'event': event,
      'settingKey': settingKey,
      'previousValue': previousValue,
      'newValue': newValue,
      'reasonCode': reasonCode,
      'provenance': SettingProvenance.user.name,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<List<ConsentRecord>> loadConsentHistory(String uid,
      {int limit = 50}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _userDoc(uid)
        .collection('consentRecords')
        .orderBy('recordedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            ConsentRecord.fromMap(d.data()))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> loadAuditHistory(String uid,
      {int limit = 50}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _userDoc(uid)
        .collection('auditEvents')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())
        .toList(growable: false);
  }

  /// Crea una solicitud de privacidad (export/erasure/disable).
  Future<PrivacyRequest> createPrivacyRequest({
    required String uid,
    required PrivacyRequestType type,
    String detail = '',
    DateTime? completeBy,
  }) async {
    final Map<String, dynamic> payload = PrivacyRequest.newRequestMap(
      type: type,
      detail: detail,
      completeBy: completeBy,
    );
    final DocumentReference<Map<String, dynamic>> ref =
        await _userDoc(uid).collection('privacyRequests').add(payload);
    final DocumentSnapshot<Map<String, dynamic>> created = await ref.get();
    return PrivacyRequest.fromMap(ref.id, created.data() ?? payload);
  }

  Future<List<PrivacyRequest>> loadPrivacyRequests(String uid,
      {int limit = 20}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _userDoc(uid)
        .collection('privacyRequests')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            PrivacyRequest.fromMap(d.id, d.data()))
        .toList(growable: false);
  }
}
