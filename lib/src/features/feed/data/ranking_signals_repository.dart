import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/ranking.dart';

/// Lee las SEÑALES de ranking precomputadas por el backend en
/// `rankingSignals/{uid}` y las convierte en [RankingSignals] para el scorer.
///
/// BACKEND-AUTORITATIVO: el cliente solo LEE (escritura solo Cloud Functions).
/// Si un uid no tiene doc, devuelve señales vacías (neutro: no rompe el feed).
/// Cachea en memoria para no releer en cada recomposición del feed.
class RankingSignalsRepository {
  RankingSignalsRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final Map<String, RankingSignals> _cache = <String, RankingSignals>{};

  // Espejo PÚBLICO con solo los scores derivados [0..1]. Los recuentos crudos
  // viven en `rankingSignals` (read:false), nunca llegan al cliente.
  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('rankingPublic');

  RankingSignals? peek(String uid) => _cache[uid];

  /// Prefetch en lote de [uids] (máx ~30 por consulta `whereIn`). Rellena la
  /// caché. Best-effort: si falla o las reglas no permiten leer, no rompe nada.
  Future<void> prefetch(Iterable<String> uids) async {
    final List<String> pending = uids
        .where((String u) => u.isNotEmpty && !_cache.containsKey(u))
        .toSet()
        .toList(growable: false);
    if (pending.isEmpty) return;
    try {
      for (int i = 0; i < pending.length; i += 30) {
        final List<String> chunk = pending.sublist(
            i, i + 30 > pending.length ? pending.length : i + 30);
        final QuerySnapshot<Map<String, dynamic>> snap =
            await _col.where(FieldPath.documentId, whereIn: chunk).get();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
          _cache[d.id] = _fromMap(d.data());
        }
        // Los que no existan: cachea neutro para no reintentar.
        for (final String u in chunk) {
          _cache.putIfAbsent(u, () => const RankingSignals());
        }
      }
    } catch (_) {/* señales no disponibles: el scorer usa neutros */}
  }

  /// Señales para un uid (de caché). Neutro si no se ha prefetched o no existe.
  RankingSignals signalsFor(String uid) =>
      _cache[uid] ?? const RankingSignals();

  RankingSignals _fromMap(Map<String, dynamic> m) {
    return RankingSignals(
      lastActiveAt: _asDate(m['recentActivityAt']),
      profileQualityOverride: _asDouble(m['profileQualityScore']),
      reciprocityOverride: _asDouble(m['reciprocityScore']),
      connectionScore: _asDouble(m['connectionScore']),
      trustSafetyScore: _asDouble(m['trustSafetyScore']),
      penalty: _asDouble(m['penalty']) ?? 0,
      newUserBoostUntil: _asDate(m['isNewUserBoostUntil']),
      exposureCount24h: _asInt(m['exposureCount24h']),
      exposureCap: _asInt(m['exposureCap']),
    );
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
