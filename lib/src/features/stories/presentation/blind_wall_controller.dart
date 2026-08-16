import 'package:flutter/foundation.dart';

import '../../feed/domain/rewind_policy.dart';
import '../domain/story.dart';

/// Una persona del muro, tal y como la ve el visor a ciegas.
///
/// Aquí NO hay estudios, trabajo, bio, intereses, prompts ni verificación, y es
/// a propósito: conocer a la persona es la RECOMPENSA del match, no su carta de
/// presentación. Añadir un campo más a esta clase se carga la idea entera de
/// Discover, así que hay un test que fija qué se puede enseñar.
@immutable
class BlindWallPerson {
  const BlindWallPerson({
    required this.uid,
    required this.displayName,
    required this.age,
    required this.stories,
  });

  final String uid;
  final String displayName;
  final int? age;

  /// Historias vivas de esta persona, de la más antigua a la más reciente (el
  /// orden en que se leen).
  final List<Story> stories;

  /// «Marta, 28», o solo el nombre cuando la edad no es pública.
  String get label {
    final int? a = age;
    if (a == null || a <= 0) return displayName;
    return '$displayName, $a';
  }
}

/// Puente entre el estado del feed y el visor a ciegas.
///
/// El visor NO habla con el backend: like, pase y Super Attra vuelven al feed,
/// que es el único que tiene el gate de likes, los contadores, las métricas
/// (feedEvents/seenProfiles), el rewind y los anuncios intercalados. Cuando el
/// visor tenía su propia ruta (`storyService.replyToStory`) la misma acción se
/// contaba distinto según desde dónde la hicieras.
class BlindWallController extends ChangeNotifier {
  BlindWallController({
    required this.beforeLike,
    required this.onLike,
    required this.onPass,
    required this.onSuperAttra,
    required this.onSkip,
    required this.onStoriesSeen,
    required this.onRewind,
    this.onSafety,
  });

  /// Gate previo al like (límite de conversaciones pendientes de Attra Clear).
  /// false = abortar sin enviar nada, igual que en la tarjeta del feed.
  final Future<bool> Function() beforeLike;
  final Future<void> Function() onLike;
  final Future<void> Function() onPass;
  final Future<void> Function() onSuperAttra;

  /// Se acabaron las historias de esta persona: se pasa a la siguiente SIN like
  /// ni pase (mirar no es opinar), pero contando la impresión.
  final VoidCallback onSkip;

  /// Historias que el usuario acaba de ver (marca de vista + contador backend).
  final void Function(List<Story> stories) onStoriesSeen;

  /// Marcha atrás. El visor NO lleva historial propio: las acciones se toman
  /// aquí pero se guardan en el feed, así que deshacer tiene que volver por el
  /// mismo puente. Una segunda pila dentro del visor se desincronizaría en
  /// cuanto el muro se recompusiera (historias que caducan, bloqueos, anuncios).
  final Future<void> Function() onRewind;

  /// Reportar / bloquear (Guideline 1.2): el contenido de una historia también
  /// tiene que poder denunciarse desde donde se ve.
  final VoidCallback? onSafety;

  BlindWallPerson? _current;
  bool _shouldClose = false;
  RewindState _rewind = const RewindState();
  String _signature = '';
  String _rewindSignature = '';

  BlindWallPerson? get current => _current;

  /// El visor se cierra solo: se acabó el muro o toca un anuncio intercalado.
  bool get shouldClose => _shouldClose;

  /// Estado de la marcha atrás tal y como lo ve el feed. El visor solo lo pinta:
  /// ni cuenta gestos ni decide tramos.
  ///
  /// No filtra nada del "a ciegas": habla del PLAN de quien mira, no de la
  /// persona que se está viendo.
  RewindState get rewind => _rewind;

  /// Vuelca el estado del feed al visor. Se llama en CADA frame del feed, así
  /// que solo notifica cuando cambia algo de verdad; si notificara siempre, el
  /// visor recargaría el vídeo en bucle.
  void sync({
    BlindWallPerson? person,
    required bool shouldClose,
    required RewindState rewind,
  }) {
    // El estado de la marcha atrás entra en la firma: si no, el botón se
    // quedaba con el número de gestos del primer volcado y no se apagaba al
    // gastar el último. Solo entra lo que se PINTA (estado y cuántos quedan),
    // no el historial entero, que cambia de identidad en cada gesto.
    final String next = shouldClose
        ? '#close'
        : person == null
            ? '#empty'
            : '${person.uid}|'
                '${person.stories.map((Story s) => s.storyId).join(',')}';
    final String rewindSignature =
        '${rewind.status.name}:${rewind.remaining}:${rewind.usedInSession}';
    if (next == _signature && rewindSignature == _rewindSignature) return;
    _signature = next;
    _rewindSignature = rewindSignature;
    _current = person;
    _shouldClose = shouldClose;
    _rewind = rewind;
    notifyListeners();
  }
}
