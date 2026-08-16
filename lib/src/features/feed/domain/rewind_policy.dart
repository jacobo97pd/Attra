import 'package:flutter/foundation.dart';

/// Gesto del feed que se puede deshacer.
///
/// El Super Attra NO está aquí a propósito: gasta saldo y el backend se niega a
/// deshacerlo (`rewind.ts`), así que enviarlo se limita a OLVIDAR el gesto
/// guardado de esa persona. Antes vaciaba el historial ENTERO, que es un
/// non sequitur: `rewind.ts` solo rechaza deshacer el propio Attra y no dice
/// nada de los likes y pases anteriores, que siguen siendo deshacibles. Gastar
/// un consumible de pago se llevaba por delante la función de pago.
enum FeedActionKind {
  like('like'),
  pass('pass');

  const FeedActionKind(this.wireName);

  /// Lo que espera `rewindFeedAction` del backend.
  final String wireName;
}

/// Tramo de marcha atrás del usuario.
///
/// Es la traducción de los entitlements a lo único que le importa a esta regla:
/// si puede deshacer y cuánto. No se lee de Firestore aquí para que la regla sea
/// pura y testeable sin backend.
enum RewindTier {
  /// No puede deshacer. El botón se ve igualmente (es el gancho) y lleva al
  /// paywall.
  free,

  /// Deshace SU ÚLTIMO gesto. No es "una vez por sesión": es que solo se guarda
  /// el último, así que cada nuevo like o pase vuelve a habilitarlo.
  plus,

  /// Deshace tantos como haya guardados en la sesión.
  pro;

  /// Traduce los flags que ya calcula `HomeShell` desde los entitlements
  /// (`hasFeature(PremiumFeature.rewind)` y `isProActive`).
  static RewindTier forPlan({
    required bool canRewind,
    required bool unlimited,
  }) {
    if (!canRewind) return RewindTier.free;
    return unlimited ? RewindTier.pro : RewindTier.plus;
  }
}

/// En qué estado está el botón de marcha atrás AHORA MISMO.
///
/// Los tres son visibles: un botón que desaparece deja al usuario adivinando si
/// la función existe, y uno que no dice nada parece roto.
enum RewindStatus {
  /// El plan no lo incluye: se ve, pero lleva al paywall.
  locked,

  /// Hay al menos un gesto guardado que se puede deshacer.
  ready,

  /// El plan lo incluye pero no hay nada que deshacer.
  empty,
}

/// Un gesto deshacible del feed.
///
/// Guarda a QUIÉN, no en qué posición estaba: el muro se recompone solo
/// (historias que caducan, bloqueos, anuncios) y la posición de entonces puede
/// apuntar ya a otra persona. Volver por índice devolvía a quien no era.
@immutable
class RewindEntry {
  const RewindEntry({required this.targetUid, required this.kind});

  final String targetUid;
  final FeedActionKind kind;

  @override
  bool operator ==(Object other) =>
      other is RewindEntry &&
      other.targetUid == targetUid &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(targetUid, kind);
}

/// Marcha atrás del feed: qué gestos hay guardados y qué puede hacer el usuario
/// con ellos según su plan.
///
/// Vive FUERA del `State` del feed a propósito. Antes la regla de los tramos
/// estaba repartida entre `_advance` (guardar uno o todos) y `_onRewind`
/// (permitir o no), así que no había forma de probarla sin montar la pantalla
/// entera con su red, sus historias y su geolocalización. Ahora el feed y el
/// visor a ciegas consumen ESTE objeto: no hay dos rutas que puedan divergir.
@immutable
class RewindState {
  const RewindState({
    this.tier = RewindTier.free,
    this.history = const <RewindEntry>[],
    this.usedInSession = false,
  });

  final RewindTier tier;

  /// Del más antiguo al más reciente: el que se deshace es el ÚLTIMO.
  final List<RewindEntry> history;

  /// El usuario ya ha deshecho algo en esta sesión. Solo sirve para el texto:
  /// "todavía no has hecho nada" y "ya lo has usado" son estados distintos y
  /// contarlos igual es lo que hace que un botón parezca roto.
  final bool usedInSession;

  /// Cuántos gestos se GUARDAN. `null` = sin límite (Pro).
  ///
  /// Free guarda uno aunque no pueda usarlo: es justo el gesto que le abre el
  /// paywall, y si al volver de comprar el historial estuviera vacío habría
  /// pagado para que el botón le dijera "no hay nada que deshacer".
  int? get storageLimit => tier == RewindTier.pro ? null : 1;

  bool get isLocked => tier == RewindTier.free;

  /// Cuántos gestos puede deshacer AHORA. Free siempre 0: guarda, pero no puede.
  int get remaining => isLocked ? 0 : history.length;

  bool get canUndo => remaining > 0;

  /// El gesto que se desharía al pulsar. `null` si no se puede deshacer nada.
  RewindEntry? get pending =>
      canUndo ? history[history.length - 1] : null;

  RewindStatus get status {
    if (isLocked) return RewindStatus.locked;
    return history.isEmpty ? RewindStatus.empty : RewindStatus.ready;
  }

  /// Guarda un gesto. Respeta el tramo: Plus (y Free) se quedan solo con el
  /// último; Pro los apila todos.
  RewindState record(RewindEntry entry) {
    final List<RewindEntry> next = <RewindEntry>[
      // Si esa persona ya estaba en el historial, su entrada vieja sobra: el
      // backend solo puede deshacer el like/dislike que hay ahora mismo, así que
      // dos entradas del mismo uid serían una marcha atrás que no deshace nada.
      ...history.where((RewindEntry e) => e.targetUid != entry.targetUid),
      entry,
    ];
    return _copyWith(history: _trim(next, storageLimit));
  }

  /// Deshace el último gesto. Si no hay nada (o el plan no lo permite) devuelve
  /// el mismo estado: quien decide qué contarle al usuario es la UI.
  RewindState undo() {
    final RewindEntry? entry = pending;
    if (entry == null) return this;
    return undoFor(entry.targetUid);
  }

  /// Deshace el gesto hacia [targetUid] concreto.
  ///
  /// Se quita POR IDENTIDAD, no por posición: la llamada al backend tarda, y en
  /// ese hueco el usuario puede haber deslizado otra tarjeta. Quitando "el
  /// último" se descartaba el gesto RECIÉN hecho (perfectamente deshacible) y se
  /// dejaba en la pila el que el servidor ya había borrado, así que la siguiente
  /// pulsación caía sobre un doc inexistente.
  ///
  /// Si ese gesto ya no está, no se marca nada: no se ha deshecho nada.
  RewindState undoFor(String targetUid) {
    if (!canUndo) return this;
    final List<RewindEntry> next = history
        .where((RewindEntry e) => e.targetUid != targetUid)
        .toList(growable: false);
    if (next.length == history.length) return this;
    return _copyWith(history: next, usedInSession: true);
  }

  /// Vacía el historial. Lo usa la recarga del feed: el pool es otro y los
  /// gestos guardados apuntaban al muro anterior.
  ///
  /// NO lo usa el Super Attra: eso borraba gestos ajenos al Attra que el backend
  /// sí sabe deshacer (ver [FeedActionKind]).
  RewindState clearHistory() => _copyWith(history: const <RewindEntry>[]);

  /// Olvida los gestos hacia [targetUid]. Lo usa el match: en cuanto hay match
  /// el backend rechaza el rewind (`failed-precondition`), así que ese gesto ya
  /// no es deshacible.
  RewindState forget(String targetUid) {
    final List<RewindEntry> next = history
        .where((RewindEntry e) => e.targetUid != targetUid)
        .toList(growable: false);
    if (next.length == history.length) return this;
    return _copyWith(history: next);
  }

  /// Reaplica el plan vigente.
  ///
  /// El plan cambia EN CALIENTE (se compra Plus desde el paywall, o caduca una
  /// suscripción mientras la app está abierta). Al bajar de tramo hay que
  /// recortar el historial: un Pro que deja de serlo no puede conservar ocho
  /// marchas atrás.
  RewindState withTier(RewindTier next) {
    if (next == tier) return this;
    return RewindState(
      tier: next,
      history: _trim(history, next == RewindTier.pro ? null : 1),
      usedInSession: usedInSession,
    );
  }

  // --- Textos. Viven aquí para que el visor a ciegas y la tarjeta del feed
  // digan LO MISMO en cada estado; repetirlos en las dos pantallas es como
  // acaban divergiendo.

  /// Etiqueta corta del botón (cabe debajo del icono).
  String get label => 'Volver';

  /// Qué pasa si pulso. Va en el tooltip y en la etiqueta de accesibilidad.
  String get hint {
    switch (status) {
      case RewindStatus.locked:
        return 'Volver atrás es de Plus y Pro';
      case RewindStatus.empty:
        return usedInSession
            ? 'Ya no queda nada que deshacer'
            : 'Todavía no hay nada que deshacer';
      case RewindStatus.ready:
        return remaining > 1
            ? 'Deshacer tu último gesto ($remaining guardados)'
            : 'Deshacer tu último gesto';
    }
  }

  /// Mensaje al pulsar sin plan. Dice qué da cada tramo: si no, "es de pago" no
  /// explica por qué merece la pena.
  String get lockedMessage =>
      'Volver atrás es de Attra Plus y Pro. Con Plus deshaces tu último gesto; '
      'con Pro, todos los que quieras.';

  /// Mensaje al pulsar sin nada guardado. Distingue "aún no has hecho nada" de
  /// "ya lo has usado", que es lo que el usuario necesita saber.
  String get emptyMessage => usedInSession
      ? 'Ya has deshecho tu último gesto. Da un like o pasa a alguien y podrás '
          'volver a deshacerlo.'
      : 'Todavía no has dado ningún like ni has pasado a nadie.';

  /// Mensaje DESPUÉS de deshacer (se lee del estado resultante).
  String get doneMessage {
    if (remaining > 0) {
      return remaining > 1
          ? 'Hecho. Puedes seguir volviendo atrás: te quedan $remaining gestos.'
          : 'Hecho. Todavía te queda otro gesto por deshacer.';
    }
    if (tier == RewindTier.plus) {
      return 'Hecho. Plus deshace un gesto cada vez: el siguiente like o pase '
          'vuelve a activar el botón.';
    }
    return 'Hecho. No queda nada más que deshacer.';
  }

  /// Contador del botón. Solo con más de uno: un "1" permanente es ruido.
  String? get counterLabel {
    if (status != RewindStatus.ready || remaining <= 1) return null;
    return remaining > 99 ? '99+' : '$remaining';
  }

  RewindState _copyWith({List<RewindEntry>? history, bool? usedInSession}) {
    return RewindState(
      tier: tier,
      history: history ?? this.history,
      usedInSession: usedInSession ?? this.usedInSession,
    );
  }

  static List<RewindEntry> _trim(List<RewindEntry> entries, int? limit) {
    if (limit == null || entries.length <= limit) {
      return List<RewindEntry>.unmodifiable(entries);
    }
    // Se recorta por delante: lo que se conserva es lo MÁS RECIENTE.
    return List<RewindEntry>.unmodifiable(
      entries.sublist(entries.length - limit),
    );
  }
}
