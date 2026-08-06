import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/ai_reference_state.dart';
import '../domain/profile_insight.dart';

/// Error de la IA visual ya CLASIFICADO. Antes solo llevaba texto crudo del
/// backend, así que la pantalla no podía distinguir "sin red" de "plan
/// caducado" y acababa enseñando el mismo mensaje mudo para todo.
class AiVisualException implements Exception {
  const AiVisualException(this.message, {this.code});
  final String message;
  final String? code;

  /// Fallo de transporte: no hay conexión o el backend no responde.
  bool get isNetwork =>
      code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'retry-limit-exceeded' ||
      code == 'network-request-failed';

  /// El plan Pro no está activo (o caducó) / no hay sesión.
  bool get isPlan => code == 'permission-denied' || code == 'unauthorized';

  /// Falta un requisito previo: consentimiento, referencia o IA deshabilitada.
  bool get isPrecondition => code == 'failed-precondition';

  bool get isAuth => code == 'unauthenticated';

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

/// Resultado de la búsqueda por PROMPT: encaje combinado [0..1] (foto + datos).
class PromptMatch {
  const PromptMatch({
    required this.uid,
    required this.score,
    this.visualScore = 0,
    this.dataScore = 0,
  });

  final String uid;
  final double score;

  /// Parte del encaje que viene de la FOTO (texto del prompt vs embedding de la
  /// foto), [0..1]. 0 si el motor visual no pudo puntuar a ese candidato.
  final double visualScore;

  /// Parte del encaje que viene de los DATOS declarados (ojos, complexión,
  /// altura, intereses, bio, prompts), [0..1].
  final double dataScore;
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

  /// El usuario borró sus datos de IA en esta sesión. Aunque queden ficheros
  /// huérfanos en Storage (si el borrado del bucket falló), NO volvemos a
  /// enseñarlos como "referencia cargada": el backend ya no tiene huella y
  /// afirmar lo contrario es mentirle al usuario sobre su privacidad.
  bool _dataCleared = false;

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

  /// Sube la foto de referencia, pide el análisis y devuelve el estado REAL.
  ///
  /// El backend responde `pending_provider` cuando guardó la foto pero no pudo
  /// calcular la huella visual: eso NO es "lista", es
  /// [AiReferenceStatus.unavailable].
  Future<AiReferenceStatus> analyzeReference({
    required String uid,
    required Uint8List bytes,
  }) async {
    final String path = 'ai/$uid/reference/${_genId()}.jpg';
    try {
      final Reference ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } on FirebaseException catch (e) {
      throw AiVisualException(_storageMessage(e), code: e.code);
    }
    final Map<String, dynamic> data;
    try {
      data = await _call('analyzeReferencePhoto', <String, dynamic>{
        'referencePath': path,
      });
    } catch (_) {
      // Si el análisis falla, la foto subida se queda huérfana en Storage: la
      // borramos para no acumular material biométrico que nadie va a usar.
      await _deleteRefs(<Reference>[_storage.ref().child(path)]);
      rethrow;
    }
    // Nueva referencia => los scores anteriores ya no valen.
    _invalidateMatchCache();
    _dataCleared = false;

    // Las referencias ANTERIORES ya no se usan (el backend solo guarda la
    // última): se quedaban en Storage para siempre. Borrado best-effort.
    await _deleteOldReferences(uid, keepPath: path);

    final String status = (data['status'] as String?) ?? 'unknown';
    switch (status) {
      case 'ready':
        return AiReferenceStatus.ready;
      case 'pending_provider':
        return AiReferenceStatus.unavailable;
      default:
        return AiReferenceStatus.unknown;
    }
  }

  /// URL de la foto de referencia ACTUAL del usuario (la más reciente en
  /// `ai/{uid}/reference/`), o null si no tiene. Lectura permitida al dueño.
  Future<String?> getReferenceUrl(String uid) async {
    if (_dataCleared) return null;
    try {
      final List<Reference> items = await _listReferences(uid);
      if (items.isEmpty) return null;
      return await items.last.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  /// Foto + estado REAL de la huella visual, en una sola llamada para la
  /// pantalla. Nunca dice "lista" sin habérselo preguntado al backend.
  Future<AiReferenceState> loadReferenceState(String uid) async {
    final String? url = await getReferenceUrl(uid);
    final AiReferenceState probe = await _probeReferenceStatus();
    if (probe.status == AiReferenceStatus.ready) {
      // El backend tiene huella. Si la foto no se pudo leer (permiso/red) el
      // estado sigue siendo válido: la búsqueda funciona igualmente.
      return AiReferenceState(status: AiReferenceStatus.ready, photoUrl: url);
    }
    if (probe.status == AiReferenceStatus.none) {
      // Sin huella en el backend. Si además queda una foto en Storage, el
      // análisis no llegó a completarse (o el borrado dejó restos).
      return AiReferenceState(
        status: url == null
            ? AiReferenceStatus.none
            : AiReferenceStatus.unavailable,
        photoUrl: url,
      );
    }
    return probe.copyWith(photoUrl: url);
  }

  /// Pregunta al backend si HAY huella visual utilizable, sin candidatos (0
  /// trabajo de IA, 0 coste de embeddings): `getVisualMatches` valida el
  /// embedding ANTES de mirar los candidatos, así que una lista vacía responde
  /// OK cuando la referencia sirve y `failed-precondition` cuando no.
  ///
  /// Devuelve `none` (sin huella), `ready`, `denied` o `unknown`.
  Future<AiReferenceState> _probeReferenceStatus() async {
    try {
      await _call('getVisualMatches', <String, dynamic>{
        'candidateUids': <String>[],
      });
      return const AiReferenceState(status: AiReferenceStatus.ready);
    } on AiVisualException catch (e) {
      if (e.isPrecondition) {
        // El backend usa failed-precondition tanto para "no hay referencia"
        // como para consentimiento/kill-switch; solo el primero menciona la
        // referencia.
        final String msg = e.message.toLowerCase();
        if (msg.contains('referencia')) {
          return const AiReferenceState(status: AiReferenceStatus.none);
        }
        return AiReferenceState(
            status: AiReferenceStatus.denied, detail: e.message);
      }
      if (e.isPlan || e.isAuth) {
        return AiReferenceState(
            status: AiReferenceStatus.denied, detail: e.message);
      }
      return AiReferenceState(
          status: AiReferenceStatus.unknown, detail: e.message);
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

  // ── Búsqueda por PROMPT (complementaria a la de foto) ────────────────────
  // Caché en memoria por prompt: recargar el feed con el mismo texto no re-pide
  // al backend salvo por uids nuevos. Se invalida al cambiar el prompt.
  String _promptKey = '';
  final Map<String, PromptMatch> _promptScoreCache = <String, PromptMatch>{};
  final Set<String> _promptQueried = <String>{};

  /// Ranking de candidatos que encajan con una DESCRIPCIÓN en lenguaje natural
  /// (físico por foto + datos declarados). Complementa `getVisualMatches` (no la
  /// sustituye). Vacío si el motor no está disponible → el feed no filtra.
  Future<List<PromptMatch>> getPromptMatches(
      String prompt, List<String> candidateUids) async {
    final String key = prompt.trim();
    if (key.isEmpty || candidateUids.isEmpty) return const <PromptMatch>[];
    // Prompt distinto → invalida la caché.
    if (key != _promptKey) {
      _promptKey = key;
      _promptScoreCache.clear();
      _promptQueried.clear();
    }
    final List<String> pending = candidateUids
        .where((String uid) => !_promptQueried.contains(uid))
        .toList(growable: false);
    if (pending.isNotEmpty) {
      final Map<String, dynamic> data =
          await _call('getPromptMatches', <String, dynamic>{
        'prompt': key,
        'candidateUids': pending,
      });
      final List<dynamic> ranking =
          (data['ranking'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic item in ranking) {
        if (item is Map) {
          final String uid = (item['uid'] ?? '').toString();
          if (uid.isEmpty) continue;
          // El backend devuelve también `visualScore` y `dataScore` (cuánto
          // pesa la foto y cuánto los datos declarados). Se descartaban, así
          // que siempre valían 0 y no había forma de explicar ni depurar el
          // encaje.
          _promptScoreCache[uid] = PromptMatch(
            uid: uid,
            score: (item['score'] as num?)?.toDouble() ?? 0.0,
            visualScore: (item['visualScore'] as num?)?.toDouble() ?? 0.0,
            dataScore: (item['dataScore'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }
      _promptQueried.addAll(pending);
    }
    final List<PromptMatch> result = <PromptMatch>[];
    for (final String uid in candidateUids) {
      final PromptMatch? match = _promptScoreCache[uid];
      if (match != null) result.add(match);
    }
    result.sort((PromptMatch a, PromptMatch b) => b.score.compareTo(a.score));
    return result;
  }

  /// Borra los datos de IA del usuario: huella visual (backend) Y las fotos de
  /// referencia de Storage. Antes solo se llamaba al backend, así que todas las
  /// fotos anteriores seguían en el bucket y la pantalla las volvía a enseñar
  /// como "Referencia cargada" pese a no haber ya ningún análisis detrás.
  Future<AiDataDeletion> clearAiData(String uid) async {
    await _call('clearAiData', <String, dynamic>{});
    // Sin referencia: la caché de similitud y la de prompt ya no aplican.
    _invalidateMatchCache();
    _promptKey = '';
    _promptScoreCache.clear();
    _promptQueried.clear();
    _dataCleared = true;
    return _deleteOldReferences(uid);
  }

  // ── Storage: listado y borrado de las fotos de referencia ────────────────

  /// Ficheros de `ai/{uid}/reference/` ordenados por nombre (el último es el
  /// más reciente: el id lleva el timestamp por delante).
  Future<List<Reference>> _listReferences(String uid) async {
    final ListResult res = await _storage.ref('ai/$uid/reference').listAll();
    return <Reference>[...res.items]
      ..sort((Reference a, Reference b) => a.name.compareTo(b.name));
  }

  /// Borra las fotos de referencia (todas, o todas menos [keepPath]).
  Future<AiDataDeletion> _deleteOldReferences(String uid,
      {String? keepPath}) async {
    List<Reference> items;
    try {
      items = await _listReferences(uid);
    } catch (_) {
      // Ni siquiera se pudo listar: no podemos afirmar que no quede nada.
      return const AiDataDeletion(
          deletedPhotos: 0, remainingPhotos: 0, verified: false);
    }
    final List<Reference> targets = keepPath == null
        ? items
        : items
            .where((Reference r) => r.fullPath != keepPath)
            .toList(growable: false);
    return _deleteRefs(targets);
  }

  Future<AiDataDeletion> _deleteRefs(List<Reference> targets) async {
    int deleted = 0;
    int remaining = 0;
    for (final Reference item in targets) {
      try {
        await item.delete();
        deleted++;
      } on FirebaseException catch (e) {
        // Si ya no existe, el objetivo está cumplido.
        if (e.code == 'object-not-found') {
          deleted++;
        } else {
          remaining++;
        }
      } catch (_) {
        remaining++;
      }
    }
    return AiDataDeletion(
        deletedPhotos: deleted, remainingPhotos: remaining, verified: true);
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
      throw AiVisualException(_functionsMessage(e), code: e.code);
    }
  }

  /// Mensajes en cristiano para los fallos de red/servidor. El texto crudo de
  /// Firebase ("UNAVAILABLE", "internal") no le dice nada al usuario.
  String _functionsMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión con Attra. Comprueba tu red e inténtalo de nuevo.';
      case 'unauthenticated':
        return 'Tu sesión ha caducado. Vuelve a entrar.';
      case 'resource-exhausted':
        return 'Demasiadas peticiones seguidas. Espera unos segundos.';
      case 'internal':
        return 'La IA ha fallado al procesar la petición. Inténtalo de nuevo.';
      default:
        return e.message ?? e.code;
    }
  }

  /// Mensajes en cristiano para los fallos de Storage (subida de la foto).
  String _storageMessage(FirebaseException e) {
    switch (e.code) {
      case 'unauthorized':
        return 'No tienes permiso para guardar la foto de referencia.';
      case 'retry-limit-exceeded':
      case 'canceled':
        return 'No se pudo subir la foto: conexión inestable. Inténtalo de nuevo.';
      case 'quota-exceeded':
        return 'No hay espacio para guardar la foto ahora mismo.';
      default:
        return 'No se pudo subir la foto (${e.code}).';
    }
  }

  String _genId() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String r = Random().nextInt(0x7FFFFFFF).toRadixString(16);
    return '${ts}_$r';
  }
}
