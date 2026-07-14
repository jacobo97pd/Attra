import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/safe_date_checkin.dart';
import '../domain/safe_date_plan.dart';
import '../domain/trusted_contact.dart';

class SafeDateException implements Exception {
  const SafeDateException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'SafeDateException($code): $message';
}

/// Fachada de Attra SafeDate para la UI. Escrituras vía Cloud Functions
/// (backend-autoritativo, validación server-side); lecturas de datos PROPIOS vía
/// Firestore (reglas: solo el dueño). Nunca expone datos del match.
class SafeDateService {
  SafeDateService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> _contactsCol(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('trustedContacts');

  // ── Contactos de confianza ───────────────────────────────────────────────

  Stream<List<TrustedContact>> observeTrustedContacts(String uid) {
    return _contactsCol(uid).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                TrustedContact.fromMap(d.id, d.data()))
            .toList(growable: false)
          ..sort((TrustedContact a, TrustedContact b) {
            if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
            return a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase());
          }));
  }

  /// Crea/actualiza un contacto. [input] ya debe estar validado por la UI.
  Future<String> saveTrustedContact(
    TrustedContactInput input, {
    String? contactId,
  }) async {
    final TrustedContactInput n = input.normalized();
    final Map<String, dynamic> data =
        await _call('saveTrustedContact', <String, dynamic>{
      'displayName': n.displayName,
      if (n.phone != null) 'phone': n.phone,
      if (n.email != null) 'email': n.email,
      'isPrimary': n.isPrimary,
      if (contactId != null) 'contactId': contactId,
    });
    return (data['contactId'] as String?) ?? '';
  }

  Future<void> deleteTrustedContact(String contactId) =>
      _call('deleteTrustedContact', <String, dynamic>{'contactId': contactId});

  // ── Planes de cita segura ────────────────────────────────────────────────

  Stream<List<SafeDatePlan>> observeMyPlans(String uid) {
    return _firestore
        .collection('safeDatePlans')
        .where('ownerUserId', isEqualTo: uid)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                SafeDatePlan.fromMap(d.id, d.data()))
            .toList(growable: false)
          ..sort((SafeDatePlan a, SafeDatePlan b) =>
              b.scheduledAt.compareTo(a.scheduledAt)));
  }

  Future<String> createPlan({
    required String chatId,
    required String placeName,
    required DateTime scheduledAt,
    String? placeAddress,
    int expectedDurationMinutes = 90,
    List<String> trustedContactIds = const <String>[],
    bool shareProfileSnapshot = false,
  }) async {
    final Map<String, dynamic> data =
        await _call('createSafeDatePlan', <String, dynamic>{
      'chatId': chatId,
      'placeName': placeName,
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      if (placeAddress != null && placeAddress.isNotEmpty)
        'placeAddress': placeAddress,
      'expectedDurationMinutes': expectedDurationMinutes,
      'trustedContactIds': trustedContactIds,
      'shareProfileSnapshot': shareProfileSnapshot,
    });
    return (data['planId'] as String?) ?? '';
  }

  Future<void> setPlanStatus(String planId, SafeDatePlanStatus status) =>
      _call('setSafeDatePlanStatus', <String, dynamic>{
        'planId': planId,
        'status': status.wireName,
      });

  // ── Check-ins ────────────────────────────────────────────────────────────

  /// Check-ins de un plan (`safeDatePlans/{planId}/checkIns`). Reglas: solo el
  /// owner del plan. Ordenados por hora prevista ascendente.
  Stream<List<SafeDateCheckIn>> observeCheckIns(String planId) {
    return _firestore
        .collection('safeDatePlans')
        .doc(planId)
        .collection('checkIns')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                SafeDateCheckIn.fromMap(d.id, d.data()))
            .toList(growable: false)
          ..sort((SafeDateCheckIn a, SafeDateCheckIn b) =>
              a.scheduledAt.compareTo(b.scheduledAt)));
  }

  /// Responde a un check-in. [response] ∈ {ok, remind_later, need_call,
  /// need_help, cancelled}. Backend valida pertenencia. NUNCA llama a nadie.
  Future<void> respondCheckIn({
    required String planId,
    required String checkInId,
    required String response,
  }) =>
      _call('respondCheckIn', <String, dynamic>{
        'planId': planId,
        'checkInId': checkInId,
        'response': response,
      });

  // ── Cita activa: ubicación temporal + alertas (Fase 4) ───────────────────

  /// Observa un plan concreto (para reflejar estado activo/alertado en la UI).
  Stream<SafeDatePlan?> observePlan(String planId) {
    return _firestore
        .collection('safeDatePlans')
        .doc(planId)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? SafeDatePlan.fromMap(d.id, d.data()!) : null);
  }

  /// Activa la ubicación en directo. Requiere consentimiento explícito
  /// ([consent] = true). El backend fija la caducidad; se borra al parar.
  Future<void> startLiveLocation(String planId, {required bool consent}) =>
      _call('startLiveLocation', <String, dynamic>{
        'planId': planId,
        'consent': consent,
      });

  Future<void> updateLiveLocation(
    String planId, {
    required double latitude,
    required double longitude,
  }) =>
      _call('updateLiveLocation', <String, dynamic>{
        'planId': planId,
        'latitude': latitude,
        'longitude': longitude,
      });

  /// Detiene y BORRA la ubicación temporal (sin historial).
  Future<void> stopLiveLocation(String planId) =>
      _call('stopLiveLocation', <String, dynamic>{'planId': planId});

  /// Registra una acción discreta. [type] ∈ {contact_me, call_me, need_exit,
  /// silent_alert, emergency}. Nunca informa al match ni llama a nadie.
  Future<void> sendAlert(String planId, String type) =>
      _call('sendSafeDateAlert', <String, dynamic>{
        'planId': planId,
        'type': type,
      });

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw SafeDateException(e.message ?? e.code, code: e.code);
    }
  }
}
