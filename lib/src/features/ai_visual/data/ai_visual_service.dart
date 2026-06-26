import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/profile_insight.dart';

class AiVisualException implements Exception {
  const AiVisualException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'AiVisualException($code): $message';
}

/// Resultado de similitud visual: un candidato y su parecido a la referencia.
class VisualMatch {
  const VisualMatch({required this.uid, required this.score});

  final String uid;

  /// Similitud coseno [-1..1]. Mayor = más parecido a la foto de referencia.
  final double score;
}

/// Fachada de la IA visual de Attra Pro (backend-autoritativo). Sube la foto de
/// referencia a Storage (privada) y delega el análisis completo al backend. El
/// embedding facial (dato biométrico) NUNCA vive ni se calcula en el cliente.
class AiVisualService {
  AiVisualService({
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  })  : _functions = functions,
        _storage = storage;

  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  // ── Caché de similitud (cliente) ─────────────────────────────────────────
  // El backend ya cachea los embeddings de Vertex por hash, así que NO se
  // recalculan. Pero `getVisualMatches` se invoca en cada recarga del feed
  // (cambio de pestaña, reload). Aquí memorizamos el score por uid bajo la
  // referencia actual: recargar con los mismos candidatos => 0 llamadas; solo
  // se pregunta al backend por uids NUEVOS. Se invalida al cambiar/borrar la
  // referencia. En memoria (no persiste entre arranques, donde ya empieza
  // limpio).
  final Map<String, double> _scoreCache = <String, double>{};

  /// uids ya consultados bajo la referencia actual (tengan score o no), para
  /// no volver a preguntar por los que el backend no pudo puntuar.
  final Set<String> _queriedUids = <String>{};

  /// Invalida la caché de similitud (la referencia cambió o se borró).
  void _invalidateMatchCache() {
    _scoreCache.clear();
    _queriedUids.clear();
  }

  /// Sube la foto de referencia y pide el análisis. Devuelve el estado
  /// (`ready` / `pending_provider`).
  Future<String> analyzeReference({
    required String uid,
    required Uint8List bytes,
  }) async {
    final String path = 'ai/$uid/reference/${_genId()}.jpg';
    try {
      final Reference ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } on FirebaseException catch (e) {
      throw AiVisualException('Error al subir: ${e.code}', code: e.code);
    }
    final Map<String, dynamic> data =
        await _call('analyzeReferencePhoto', <String, dynamic>{
      'referencePath': path,
    });
    // Nueva referencia => los scores anteriores ya no valen.
    _invalidateMatchCache();
    return (data['status'] as String?) ?? 'unknown';
  }

  /// URL de la foto de referencia ACTUAL del usuario (la más reciente en
  /// `ai/{uid}/reference/`), o null si no tiene. Lectura permitida al dueño.
  Future<String?> getReferenceUrl(String uid) async {
    try {
      final ListResult res = await _storage.ref('ai/$uid/reference').listAll();
      if (res.items.isEmpty) return null;
      final List<Reference> items = <Reference>[...res.items]
        ..sort((Reference a, Reference b) => a.name.compareTo(b.name));
      return await items.last.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<List<ProfileInsight>> getInsights() async {
    final Map<String, dynamic> data =
        await _call('getProfileInsights', <String, dynamic>{});
    final List<dynamic> raw =
        (data['insights'] as List<dynamic>?) ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((Map<dynamic, dynamic> m) => ProfileInsight.fromMap(
            m.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))))
        .toList(growable: false);
  }

  /// Ranking de candidatos por parecido estético a la referencia: lista de
  /// (uid, score) ordenada de más a menos parecido. Vacío si no hay referencia
  /// o el motor no está disponible (en ese caso el feed no filtra ni reordena).
  ///
  /// `score` es la similitud coseno [-1..1] del embedding (mayor = más parecido).
  Future<List<VisualMatch>> getVisualMatches(List<String> candidateUids) async {
    if (candidateUids.isEmpty) return const <VisualMatch>[];

    // Solo preguntamos al backend por los uids que NO hemos consultado todavía
    // bajo la referencia actual. El resto sale de la caché en memoria.
    final List<String> pending = candidateUids
        .where((String uid) => !_queriedUids.contains(uid))
        .toList(growable: false);

    if (pending.isNotEmpty) {
      final Map<String, dynamic> data =
          await _call('getVisualMatches', <String, dynamic>{
        'candidateUids': pending,
      });
      final List<dynamic> ranking =
          (data['ranking'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic item in ranking) {
        if (item is Map) {
          final String uid = (item['uid'] ?? '').toString();
          if (uid.isEmpty) continue;
          _scoreCache[uid] = (item['score'] as num?)?.toDouble() ?? 0.0;
        }
      }
      // Marcamos TODOS los pedidos como consultados (aunque el backend no los
      // puntuara) para no volver a preguntar por ellos en cada recarga.
      _queriedUids.addAll(pending);
    }

    // Construimos el resultado desde la caché, ordenado de más a menos parecido.
    final List<VisualMatch> result = <VisualMatch>[];
    for (final String uid in candidateUids) {
      final double? score = _scoreCache[uid];
      if (score != null) result.add(VisualMatch(uid: uid, score: score));
    }
    result.sort((VisualMatch a, VisualMatch b) => b.score.compareTo(a.score));
    return result;
  }

  Future<void> clearAiData() async {
    await _call('clearAiData', <String, dynamic>{});
    // Sin referencia: la caché de similitud ya no aplica.
    _invalidateMatchCache();
  }

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
      throw AiVisualException(e.message ?? e.code, code: e.code);
    }
  }

  String _genId() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String r = Random().nextInt(0x7FFFFFFF).toRadixString(16);
    return '${ts}_$r';
  }
}
