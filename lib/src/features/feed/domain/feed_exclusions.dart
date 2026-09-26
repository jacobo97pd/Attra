import 'package:flutter/foundation.dart';

/// Lecturas de las que salen las exclusiones del feed. Cada una se hace por
/// separado para que el fallo de una no se lleve por delante a las demás.
enum ExclusionSource { likes, dislikes, matches, blocks }

/// A quién NO se enseña en el feed, separado POR MOTIVO.
///
/// Antes era un único `Set` que mezclaba likes, pases, matches y bloqueos, y la
/// "segunda vuelta" le restaba todos los pases: quien estaba excluido por un
/// pase Y por un bloqueo (o un match) perdía las dos exclusiones a la vez,
/// porque un conjunto no recuerda por qué está cada uno. Así volvían al feed la
/// persona bloqueada, la que TE había bloqueado (delatando el bloqueo al darle
/// like) y a quien ya le habías mandado un Attra. Separado por motivo, la
/// segunda vuelta solo puede reponer pases y lo duro se queda siempre fuera.
@immutable
class FeedExclusions {
  const FeedExclusions({
    this.liked = const <String>{},
    this.passed = const <String>{},
    this.permanentlyPassed = const <String>{},
    this.matched = const <String>{},
    this.blocked = const <String>{},
    this.failed = const <ExclusionSource>{},
  });

  /// Todas las lecturas fallaron (p.ej. la llamada entera lanzó).
  static const FeedExclusions unavailable = FeedExclusions(
    failed: <ExclusionSource>{
      ExclusionSource.likes,
      ExclusionSource.dislikes,
      ExclusionSource.matches,
      ExclusionSource.blocks,
    },
  );

  /// Likes y Attras enviados (cualquier estado: también los cancelados por un
  /// bloqueo o un unmatch).
  final Set<String> liked;

  /// Pases normales: son los ÚNICOS que la segunda vuelta puede reponer.
  final Set<String> passed;

  /// Pases que no se deshacen nunca: los que escriben el reporte y la
  /// moderación del directo ("no volver a verse"). Se guardan como dislikes con
  /// `source`, pero son de seguridad, no de gusto.
  final Set<String> permanentlyPassed;

  /// La otra persona de cada match, en CUALQUIER estado. Incluye 'blocked': las
  /// reglas no dejan leer los bloqueos que otro te hizo, así que ese match es la
  /// única señal que tiene el cliente de que alguien le bloqueó.
  final Set<String> matched;

  /// Bloqueos que hice yo.
  final Set<String> blocked;

  /// Lecturas que fallaron en esta carga (sus conjuntos vienen vacíos, que NO
  /// es lo mismo que "no hay nadie").
  final Set<ExclusionSource> failed;

  bool get complete => failed.isEmpty;

  /// Exclusiones que nada puede levantar: ni la segunda vuelta.
  Set<String> get hard => <String>{
        ...liked,
        ...permanentlyPassed,
        ...matched,
        ...blocked,
      };

  /// Pases que la segunda vuelta puede volver a enseñar: los normales que no
  /// estén además excluidos por algo duro. Es también la cifra que promete el
  /// estado vacío ("las N personas que pasaste"): contando bloqueados o
  /// matcheados ofrecía una segunda vuelta que luego salía vacía.
  Set<String> get secondRoundCandidates => passed.difference(hard);

  /// Lo que se excluye del pool: en el feed normal, lo duro y los pases; en la
  /// segunda vuelta, solo lo duro (los pases se vuelven a ver).
  Set<String> excludedFor({required bool secondRound}) =>
      secondRound ? hard : <String>{...hard, ...passed};

  /// ¿Un dislike con este `source` se puede reconsiderar en la segunda vuelta?
  /// El pase del feed no lleva `source` y el del directo lleva 'live'; todo lo
  /// demás ('live_report', 'live_moderation' o cualquier motivo nuevo) se trata
  /// como permanente: ante la duda, no se vuelve a enseñar a nadie.
  static bool isReconsiderablePass(Object? source) {
    if (source == null) return true;
    if (source is! String) return false;
    final String s = source.trim();
    return s.isEmpty || s == 'feed' || s == 'live';
  }

  /// Construye las exclusiones a partir de los documentos de cada lectura. Un
  /// `null` en una lectura significa que FALLÓ (y se apunta en [failed]).
  ///
  /// Puro para poder probar la clasificación sin Firestore.
  static FeedExclusions fromDocs({
    required String uid,
    Iterable<Map<String, dynamic>>? likes,
    Iterable<Map<String, dynamic>>? dislikes,
    Iterable<Map<String, dynamic>>? matches,
    Iterable<Map<String, dynamic>>? blocks,
  }) {
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    final Set<String> liked = <String>{
      for (final Map<String, dynamic> d
          in likes ?? const <Map<String, dynamic>>[])
        if (str(d['toUid']) case final String to) to,
    };
    final Set<String> passed = <String>{};
    final Set<String> permanent = <String>{};
    for (final Map<String, dynamic> d
        in dislikes ?? const <Map<String, dynamic>>[]) {
      final String? to = str(d['toUid']);
      if (to == null) continue;
      (isReconsiderablePass(d['source']) ? passed : permanent).add(to);
    }
    final Set<String> matched = <String>{
      for (final Map<String, dynamic> d
          in matches ?? const <Map<String, dynamic>>[])
        if (d['users'] is List)
          for (final Object? u in d['users'] as List<Object?>)
            if (u is String && u.isNotEmpty && u != uid) u,
    };
    final Set<String> blocked = <String>{
      for (final Map<String, dynamic> d
          in blocks ?? const <Map<String, dynamic>>[])
        if (str(d['blockedUid']) case final String b) b,
    };
    return FeedExclusions(
      liked: liked,
      passed: passed,
      permanentlyPassed: permanent,
      matched: matched,
      blocked: blocked,
      failed: <ExclusionSource>{
        if (likes == null) ExclusionSource.likes,
        if (dislikes == null) ExclusionSource.dislikes,
        if (matches == null) ExclusionSource.matches,
        if (blocks == null) ExclusionSource.blocks,
      },
    );
  }

  /// Cubre las lecturas que fallaron con las de una carga anterior BUENA.
  ///
  /// Devuelve null si alguna falló y no hay con qué cubrirla: quien llama NO
  /// puede seguir como si no hubiera nadie excluido (fallar "abierto" enseñaba
  /// matches y bloqueados por un simple bache al refrescar el token). Ninguna
  /// categoría es prescindible: los pases llevan también los permanentes del
  /// directo, y sin ellos volvería a salir la persona reportada.
  FeedExclusions? coveredBy(FeedExclusions? previous) {
    if (complete) return this;
    if (previous == null || !previous.complete) return null;
    bool miss(ExclusionSource s) => failed.contains(s);
    return FeedExclusions(
      liked: miss(ExclusionSource.likes) ? previous.liked : liked,
      passed: miss(ExclusionSource.dislikes) ? previous.passed : passed,
      permanentlyPassed: miss(ExclusionSource.dislikes)
          ? previous.permanentlyPassed
          : permanentlyPassed,
      matched: miss(ExclusionSource.matches) ? previous.matched : matched,
      blocked: miss(ExclusionSource.blocks) ? previous.blocked : blocked,
    );
  }

  /// Bloqueo hecho en esta sesión (aún no releído del servidor).
  FeedExclusions withBlocked(String uid) => FeedExclusions(
        liked: liked,
        passed: passed,
        permanentlyPassed: permanentlyPassed,
        matched: matched,
        blocked: <String>{...blocked, uid},
        failed: failed,
      );

  /// Marcha atrás de un like o un pase: deja de estar decidido. Lo duro (match,
  /// bloqueo, pase permanente) no se toca: eso no se deshace.
  FeedExclusions withoutGesture(String uid) => FeedExclusions(
        liked: <String>{...liked}..remove(uid),
        passed: <String>{...passed}..remove(uid),
        permanentlyPassed: permanentlyPassed,
        matched: matched,
        blocked: blocked,
        failed: failed,
      );
}
