import 'package:flutter/foundation.dart';

import '../../profile/domain/profile_state.dart';
import 'story.dart';

/// Muro de historias ya resuelto: a quién se pinta y por dónde va el usuario.
@immutable
class StoryWall {
  const StoryWall({required this.profiles, required this.index});

  final List<SeedProfile> profiles;

  /// Posición actual dentro de [profiles]. `profiles.length` significa "se
  /// acabó el muro": es un estado válido al que hay que poder llegar Y en el que
  /// hay que poder quedarse.
  final int index;

  bool get isExhausted => index >= profiles.length;
}

/// Cruza el pool ya ordenado por el pipeline del feed con quien tiene historias
/// vivas, y decide dónde queda el índice.
///
/// El ORDEN lo pone el pipeline (filtros, ranking orgánico, Boost pagado, modo
/// viaje, Slow Dating, IA, "te dio like"), no las historias: estas solo deciden
/// QUIÉN se pinta. Si el muro reordenara por historia se perdería todo eso.
///
/// Es una función PURA a propósito: esta regla vivía dentro del `State` del feed
/// y el test la reimplementaba a mano, así que los tests pasaban en verde sin
/// ejecutar una sola línea de lo que corre en producción (y no cubrían lo único
/// que fallaba, la recolocación del índice).
StoryWall buildStoryWall({
  required List<SeedProfile> rankedPool,
  required Map<String, List<Story>> storiesByOwner,
  bool wallActive = true,
  Set<String> excludedUids = const <String>{},
  Set<String> consumedUids = const <String>{},
  String? currentUid,
}) {
  final List<SeedProfile> wall = rankedPool
      .where((SeedProfile p) =>
          !excludedUids.contains(p.id) &&
          (!wallActive || _hasLiveStory(storiesByOwner[p.id])))
      .toList(growable: false);

  // Si la persona que se estaba viendo sigue en el muro, no se salta de sitio al
  // llegar historias nuevas (el stream es global: emite hasta cuando alguien, en
  // cualquier parte de la app, ve una historia ajena).
  int index = currentUid == null
      ? -1
      : wall.indexWhere((SeedProfile p) => p.id == currentUid);
  if (index < 0) {
    // Ya no está (le caducó la historia, se le ha bloqueado) o el muro se había
    // terminado. Volver a 0 reponía a quien ya se había likeado o pasado en esta
    // sesión: se salta a la primera persona todavía sin decidir y, si no queda
    // ninguna, se CONSERVA el estado de "se acabó".
    index = wall.indexWhere((SeedProfile p) => !consumedUids.contains(p.id));
    if (index < 0) index = wall.length;
  }
  return StoryWall(profiles: wall, index: index);
}

/// Red de seguridad ante una historia caducada que el backend todavía no ha
/// marcado `expired` (el limpiador programado corre cada hora).
bool _hasLiveStory(List<Story>? stories) =>
    stories != null && stories.any((Story s) => s.isLive);
