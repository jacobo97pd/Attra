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

/// Rasgos que el backend saca de la foto de referencia con Cloud Vision, en la
/// MISMA llamada que ya hacía falta para recortar la cara (coste cero extra).
///
/// Aquí NO hay etnia, edad ni sexo: Cloud Vision no los devuelve y no se
/// deducen. Tampoco gafas, por lo mismo. Y el embedding (dato biométrico) no
/// llega nunca al cliente: esto describe la FOTO, no identifica a nadie.
class ReferenceTraits {
  const ReferenceTraits({
    required this.detected,
    required this.faceCount,
    required this.confidence,
    required this.pose,
    required this.panAngle,
    required this.tiltAngle,
    required this.rollAngle,
    required this.smile,
    required this.headwear,
    required this.blurred,
    required this.underExposed,
    required this.faceAreaRatio,
    required this.faceCropped,
    this.engineFailed = false,
  });

  factory ReferenceTraits.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0.0;
    String s(String k) => (m[k] as String?) ?? 'UNKNOWN';
    return ReferenceTraits(
      detected: m['detected'] == true,
      faceCount: (m['faceCount'] as num?)?.toInt() ?? 0,
      confidence: d('confidence'),
      pose: s('pose'),
      panAngle: d('panAngle'),
      tiltAngle: d('tiltAngle'),
      rollAngle: d('rollAngle'),
      smile: s('smile'),
      headwear: s('headwear'),
      blurred: s('blurred'),
      underExposed: s('underExposed'),
      faceAreaRatio: d('faceAreaRatio'),
      faceCropped: m['faceCropped'] == true,
      engineFailed: m['engineFailed'] == true,
    );
  }

  final bool detected;
  final int faceCount;
  final double confidence;

  /// `frontal` | `three_quarter` | `profile` | `unknown`.
  final String pose;
  final double panAngle;
  final double tiltAngle;
  final double rollAngle;

  /// Likelihood de Cloud Vision: VERY_UNLIKELY..VERY_LIKELY, o UNKNOWN.
  final String smile;
  final String headwear;
  final String blurred;
  final String underExposed;

  /// Fracción de la foto que ocupa la cara.
  final double faceAreaRatio;

  /// Si es false, el parecido se calculó sobre la foto ENTERA (no se detectó
  /// cara) y por tanto vale menos. Se dice, no se disimula.
  final bool faceCropped;

  /// Falló el MOTOR (Cloud Vision / Vertex no respondieron), no la foto. Con
  /// esto a true, `detected: false` no significa "tu foto no tiene cara".
  final bool engineFailed;

  /// Motivos por los que esta foto de referencia va a dar peores resultados.
  /// Vacío = la foto sirve bien.
  List<String> get warnings {
    final List<String> out = <String>[];
    // El motor caído NO es un defecto de la foto del usuario. Decirle "no se ha
    // detectado ninguna cara" durante una caída de Cloud Vision le hace borrar
    // un retrato perfectamente válido y probar otro, y otro.
    if (engineFailed) {
      out.add('No hemos podido analizar tu foto ahora mismo: ha fallado el '
          'motor de IA, no tu foto. Vuelve a intentarlo en un momento.');
      return out;
    }
    if (!detected) {
      out.add('No se ha detectado ninguna cara: el parecido se calcula sobre '
          'la foto entera y será mucho menos fiable.');
      return out;
    }
    if (faceCount > 1) {
      out.add('Hay $faceCount caras en la foto. Se ha usado la más grande; '
          'para acertar mejor, sube una foto de una sola persona.');
    }
    if (faceAreaRatio < 0.05) {
      out.add('La cara ocupa muy poco de la foto: recórtala más cerca.');
    }
    if (pose == 'profile') {
      out.add('La cara está muy de perfil. De frente funciona mejor.');
    }
    if (blurred == 'LIKELY' || blurred == 'VERY_LIKELY') {
      out.add('La foto se ve movida o desenfocada.');
    }
    if (underExposed == 'LIKELY' || underExposed == 'VERY_LIKELY') {
      out.add('La foto está muy oscura.');
    }
    return out;
  }
}

/// Resultado de analizar la foto de referencia: estado + rasgos de la foto.
class ReferenceAnalysis {
  const ReferenceAnalysis({required this.status, this.traits});

  final AiReferenceStatus status;
  final ReferenceTraits? traits;
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

/// Ranking + si está COMPLETO.
///
/// Antes esto era una lista pelada: si el motor no podía puntuar a la mitad de
/// los candidatos (pasa de verdad — el 38% de las llamadas a Vertex responden
/// HTTP 429 por cuota), el usuario Pro veía un ranking corto sin ninguna señal
/// de que faltaba gente. Un resultado incompleto que se presenta como completo
/// es peor que un error.
class VisualRanking {
  const VisualRanking({
    required this.matches,
    this.complete = true,
    this.skipped = 0,
    this.threshold,
    this.traits,
  });

  final List<VisualMatch> matches;

  /// false = el motor no pudo puntuar a todos los candidatos.
  final bool complete;

  /// Cuántos candidatos se quedaron sin puntuar por fallo del motor.
  final int skipped;

  /// Corte de parecido que manda el BACKEND. El umbral y el preprocesado son la
  /// misma decisión (los cosenos cambian de escala al cambiar el pipeline), así
  /// que tenerlo aquí fijo obligaba a desplegar la app para recalibrar. null =
  /// backend antiguo; el cliente usa su valor de respaldo.
  final double? threshold;

  /// Rasgos de la foto de referencia, para poder repintar el panel al volver a
  /// entrar sin tener que re-analizar la foto.
  final ReferenceTraits? traits;
}

/// Lo mismo para la búsqueda por descripción.
class PromptRanking {
  const PromptRanking({
    required this.matches,
    this.complete = true,
    this.skipped = 0,
    this.visualDisabled = false,
    this.signals = const <String>[],
    this.threshold,
  });

  final List<PromptMatch> matches;
  final bool complete;
  final int skipped;

  /// El prompt no se pudo convertir a embedding: el orden sale SÓLO de los
  /// datos declarados. Es un resultado peor, no uno equivalente.
  final bool visualDisabled;

  /// Lo que el buscador ENTENDIÓ de la frase, ya en castellano y listo para
  /// pintar ("chico", "alto", "fuerte", "majo"). El backend lo mandaba desde el
  /// principio y el cliente lo tiraba, así que el usuario no tenía forma de
  /// saber por qué salían esos perfiles — que era la mitad del encargo.
  final List<String> signals;

  /// Corte que manda el backend. Hoy es 0: el filtrado por lo que el usuario
  /// pidió (género, datos declarados) ya se hace allí, y volver a filtrar aquí
  /// por el score combinado sólo quitaba buenos resultados.
  final double? threshold;
}

/// Traduce las señales del backend a etiquetas que se puedan enseñar tal cual.
/// Sólo se nombran cosas que el usuario ha escrito; no se inventa nada.
List<String> _readSignals(Map<String, dynamic>? m) {
  if (m == null) return const <String>[];
  const Map<String, String> gender = <String, String>{
    'male': 'chico',
    'female': 'chica',
    'non_binary': 'no binario',
  };
  const Map<String, String> eyes = <String, String>{
    'blue': 'ojos azules',
    'green': 'ojos verdes',
    'brown': 'ojos marrones',
    'hazel': 'ojos avellana',
    'gray': 'ojos grises',
    'black': 'ojos negros',
  };
  const Map<String, String> hair = <String, String>{
    'black': 'pelo negro',
    'brown': 'pelo castaño',
    'blonde': 'rubio',
    'red': 'pelirrojo',
    'gray': 'canoso',
  };
  const Map<String, String> body = <String, String>{
    'athletic': 'atlético',
    'muscular': 'fuerte',
    'slim': 'delgado',
    'curvy': 'con curvas',
    'average': 'complexión media',
    'plus': 'grande',
  };
  const Map<String, String> personality = <String, String>{
    'empathetic': 'majo',
    'fun': 'divertido',
    'calm': 'tranquilo',
    'ambitious': 'ambicioso',
    'creative': 'creativo',
    'intense': 'intenso',
  };
  List<String> pick(String key, Map<String, String> table) => <String>[
        for (final dynamic v in (m[key] as List<dynamic>?) ?? const <dynamic>[])
          if (table[v.toString()] != null) table[v.toString()]!,
      ];
  final List<String> out = <String>[];
  final String g = (m['gender'] ?? 'any').toString();
  if (gender[g] != null) out.add(gender[g]!);
  final String h = (m['heightPref'] ?? 'any').toString();
  if (h == 'tall') out.add('alto');
  if (h == 'short') out.add('bajito');
  out
    ..addAll(pick('bodyTypes', body))
    ..addAll(pick('eyeColors', eyes))
    ..addAll(pick('hairColors', hair))
    ..addAll(pick('personality', personality));
  return out;
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
  Future<ReferenceAnalysis> analyzeReference({
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
    final Object? rawTraits = data['traits'];
    final ReferenceTraits? traits = rawTraits is Map
        ? ReferenceTraits.fromMap(rawTraits
            .map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
        : null;
    switch (status) {
      case 'ready':
        return ReferenceAnalysis(
            status: AiReferenceStatus.ready, traits: traits);
      case 'pending_provider':
        return ReferenceAnalysis(
            status: AiReferenceStatus.unavailable, traits: traits);
      default:
        return ReferenceAnalysis(
            status: AiReferenceStatus.unknown, traits: traits);
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

  /// Rasgos de la referencia vistos en la última sonda. `analyzeReferencePhoto`
  /// los persiste en `aiReferences/{uid}.traits`, pero `aiReferences` es
  /// backend-only: sin devolverlos aquí, el panel "lo que la IA ha leído de tu
  /// foto" sólo se veía en la sesión en la que se subía la foto y desaparecía al
  /// reabrir la pantalla, pese a estar guardados.
  ReferenceTraits? _lastReferenceTraits;
  ReferenceTraits? get lastReferenceTraits => _lastReferenceTraits;

  /// Pregunta al backend si HAY huella visual utilizable, sin candidatos:
  /// `getVisualMatches` valida el embedding ANTES de mirar los candidatos, así
  /// que una lista vacía responde OK cuando la referencia sirve.
  ///
  /// NO es gratis: si la referencia todavía es de la v1, esta llamada dispara su
  /// migración (descarga de Storage + Cloud Vision + Vertex). Ocurre UNA vez por
  /// usuario; el coste está en `ai.ts`.
  ///
  /// Devuelve `none` (sin huella), `ready`, `denied` o `unknown`. Un fallo
  /// transitorio del motor llega como `unavailable` y cae en `unknown`, NO en
  /// `none`: decirle "no tienes referencia" a quien sí la tiene le empujaba a
  /// volver a subir la foto por una caída nuestra.
  Future<AiReferenceState> _probeReferenceStatus() async {
    try {
      final Map<String, dynamic> data =
          await _call('getVisualMatches', <String, dynamic>{
        'candidateUids': <String>[],
      });
      final Map<dynamic, dynamic>? rawTraits = data['traits'] as Map?;
      _lastReferenceTraits = rawTraits == null
          ? null
          : ReferenceTraits.fromMap(rawTraits.map((dynamic k, dynamic v) =>
              MapEntry<String, dynamic>(k.toString(), v)));
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
  Future<VisualRanking> getVisualMatches(List<String> candidateUids) async {
    if (candidateUids.isEmpty) {
      return const VisualRanking(matches: <VisualMatch>[]);
    }

    // Solo preguntamos al backend por los uids que NO hemos consultado todavía
    // bajo la referencia actual. El resto sale de la caché en memoria.
    final List<String> pending = candidateUids
        .where((String uid) => !_queriedUids.contains(uid))
        .toList(growable: false);

    bool complete = true;
    int skipped = 0;
    double? threshold;
    ReferenceTraits? traits;
    if (pending.isNotEmpty) {
      final Map<String, dynamic> data =
          await _call('getVisualMatches', <String, dynamic>{
        'candidateUids': pending,
      });
      threshold = (data['threshold'] as num?)?.toDouble();
      final Map<dynamic, dynamic>? rawTraits = data['traits'] as Map?;
      if (rawTraits != null) {
        traits = ReferenceTraits.fromMap(rawTraits.map(
            (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v)));
      }
      final List<dynamic> ranking =
          (data['ranking'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic item in ranking) {
        if (item is Map) {
          final String uid = (item['uid'] ?? '').toString();
          if (uid.isEmpty) continue;
          _scoreCache[uid] = (item['score'] as num?)?.toDouble() ?? 0.0;
        }
      }
      // Los que el motor NO pudo puntuar (cuota de Vertex, motor caído) NO se
      // marcan como consultados: el fallo es transitorio y hay que reintentarlo
      // en la siguiente recarga. Antes se marcaban todos y esos candidatos
      // quedaban excluidos para siempre bajo esta referencia.
      final Set<String> failed = <String>{
        for (final dynamic u in (data['skippedUids'] as List<dynamic>?) ??
            const <dynamic>[])
          u.toString(),
      };
      _queriedUids
          .addAll(pending.where((String uid) => !failed.contains(uid)));
      complete = data['complete'] != false;
      skipped = (data['skipped'] as num?)?.toInt() ?? failed.length;
    }

    // Construimos el resultado desde la caché, ordenado de más a menos parecido.
    final List<VisualMatch> result = <VisualMatch>[];
    for (final String uid in candidateUids) {
      final double? score = _scoreCache[uid];
      if (score != null) result.add(VisualMatch(uid: uid, score: score));
    }
    result.sort((VisualMatch a, VisualMatch b) => b.score.compareTo(a.score));
    return VisualRanking(
      matches: result,
      complete: complete,
      skipped: skipped,
      threshold: threshold,
      traits: traits,
    );
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
  Future<PromptRanking> getPromptMatches(
      String prompt, List<String> candidateUids) async {
    final String key = prompt.trim();
    if (key.isEmpty || candidateUids.isEmpty) {
      return const PromptRanking(matches: <PromptMatch>[]);
    }
    // Prompt distinto → invalida la caché.
    if (key != _promptKey) {
      _promptKey = key;
      _promptScoreCache.clear();
      _promptQueried.clear();
    }
    final List<String> pending = candidateUids
        .where((String uid) => !_promptQueried.contains(uid))
        .toList(growable: false);
    bool complete = true;
    int skipped = 0;
    bool visualDisabled = false;
    double? promptThreshold;
    List<String> signals = const <String>[];
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
      // Igual que en getVisualMatches: los que fallaron por cuota NO se marcan
      // como consultados, para que la siguiente recarga vuelva a intentarlos.
      final Set<String> failed = <String>{
        for (final dynamic u in (data['skippedUids'] as List<dynamic>?) ??
            const <dynamic>[])
          u.toString(),
      };
      _promptQueried
          .addAll(pending.where((String uid) => !failed.contains(uid)));
      complete = data['complete'] != false;
      skipped = (data['skipped'] as num?)?.toInt() ?? failed.length;
      visualDisabled = data['visualDisabled'] == true;
      promptThreshold = (data['threshold'] as num?)?.toDouble();
      final Map<dynamic, dynamic>? rawSignals = data['signals'] as Map?;
      signals = _readSignals(rawSignals?.map(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v)));
    }
    final List<PromptMatch> result = <PromptMatch>[];
    for (final String uid in candidateUids) {
      final PromptMatch? match = _promptScoreCache[uid];
      if (match != null) result.add(match);
    }
    result.sort((PromptMatch a, PromptMatch b) => b.score.compareTo(a.score));
    return PromptRanking(
      matches: result,
      complete: complete,
      skipped: skipped,
      visualDisabled: visualDisabled,
      signals: signals,
      threshold: promptThreshold,
    );
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
    // Los rasgos son datos derivados de la cara: si el usuario retira el
    // consentimiento, no pueden seguir en memoria del cliente.
    _lastReferenceTraits = null;
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
