import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../domain/boost.dart';

class BoostServiceException implements Exception {
  const BoostServiceException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'BoostServiceException($code): $message';
}

/// Fachada de Boosts consumibles.
///
/// Las escrituras (activar, impresiones, resumen) pasan por Cloud Functions.
/// La lectura de `activeBoosts` para ordenar el feed usa documentos mínimos y
/// solo después de que el feed ya aplicó sus filtros duros.
class BoostService {
  BoostService({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Abona consumibles al saldo (PLACEHOLDER de compra; en producción se llama
  /// tras validar el recibo IAP). [kind] = 'boost' | 'swipe'. Devuelve el saldo
  /// resultante.
  Future<int> purchaseConsumable({
    required String kind,
    int amount = 1,
    String? purchaseId,
  }) async {
    final Map<String, dynamic> data = await _call('grantConsumable', <String, dynamic>{
      'kind': kind,
      'amount': amount,
      if (purchaseId != null) 'purchaseId': purchaseId,
    });
    return (data['balance'] as num?)?.toInt() ?? 0;
  }

  Future<BoostActivationResult> activateBoost({
    BoostType type = BoostType.boostNormal,
  }) async {
    final Map<String, dynamic> data = await _call(
      'activateBoost',
      <String, dynamic>{'type': type.wireName},
    );
    return BoostActivationResult.fromMap(data);
  }

  Future<ActiveBoost?> getActiveBoost() async {
    final Map<String, dynamic> data =
        await _call('getActiveBoostForUser', const <String, dynamic>{});
    final Object? raw = data['activeBoost'];
    if (raw is! Map) return null;
    return ActiveBoost.fromMap(
      (raw['userId'] ?? '').toString(),
      raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
    );
  }

  Stream<ActiveBoost?> watchActiveBoost(String uid) {
    final String normalized = uid.trim();
    if (normalized.isEmpty) return const Stream<ActiveBoost?>.empty();
    return _firestore
        .collection('activeBoosts')
        .doc(normalized)
        .snapshots()
        .map((DocumentSnapshot<Map<String, dynamic>> snap) {
      final Map<String, dynamic>? data = snap.data();
      if (!snap.exists || data == null) return null;
      final ActiveBoost boost = ActiveBoost.fromMap(snap.id, data);
      return boost.isActiveAt(DateTime.now()) ? boost : null;
    });
  }

  Future<BoostSummary> getBoostSummary(String boostId) async {
    final Map<String, dynamic> data = await _call(
      'getBoostSummary',
      <String, dynamic>{'boostId': boostId},
    );
    return BoostSummary.fromMap(data);
  }

  Future<Map<String, ActiveBoost>> fetchActiveBoostsForUsers(
    Iterable<String> uids,
  ) async {
    final List<String> ids = uids
        .map((String uid) => uid.trim())
        .where((String uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, ActiveBoost>{};

    final Map<String, ActiveBoost> out = <String, ActiveBoost>{};
    for (int i = 0; i < ids.length; i += 10) {
      final List<String> chunk =
          ids.skip(i).take(10).toList(growable: false);
      final QuerySnapshot<Map<String, dynamic>> snap = await _firestore
          .collection('activeBoosts')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snap.docs) {
        final ActiveBoost boost = ActiveBoost.fromMap(doc.id, doc.data());
        if (boost.isActiveAt(DateTime.now())) {
          out[doc.id] = boost;
        }
      }
    }
    return out;
  }

  Future<void> recordBoostImpression(
    String boostedUid, {
    String? feedEventId,
  }) async {
    final String uid = boostedUid.trim();
    if (uid.isEmpty) return;
    try {
      await _call('recordBoostImpression', <String, dynamic>{
        'boostedUid': uid,
        if (feedEventId != null && feedEventId.trim().isNotEmpty)
          'feedEventId': feedEventId.trim(),
      });
    } on BoostServiceException catch (e) {
      if (kDebugMode) debugPrint('[Attra][Boost] impresion fallo: $e');
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw BoostServiceException(e.message ?? e.code, code: e.code);
    }
  }
}
