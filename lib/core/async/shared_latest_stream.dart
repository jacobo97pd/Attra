import 'dart:async';

/// Comparte UNA suscripción a [source] entre todos sus oyentes y repite el
/// último valor a quien llega tarde.
///
/// POR QUÉ: la campana de notificaciones y la lista de Chats piden su stream
/// dentro de build(). Si cada llamada abría consultas nuevas, cada repintado
/// del HomeShell (p. ej. al plegar la cabecera del feed) cerraba y reabría sus
/// escuchas de Firestore, y desde que esos streams apartan bloqueos y matches
/// deshechos son dos o tres consultas por stream. Guardando la instancia que
/// devuelve esto (una por uid), StreamBuilder recibe el MISMO stream y no se
/// re-suscribe; y un oyente nuevo (otra pantalla, un widget recreado) recibe
/// al momento lo último conocido en vez de quedarse cargando.
///
/// [source] se abre con el primer oyente y se cancela con el último: no queda
/// ninguna consulta viva sin nadie mirando. Al volver a abrirse se pide de
/// nuevo y no se repite un valor viejo. Si [source] termina (Firestore cierra
/// el stream tras un error), se cierra para todos y el siguiente oyente lo
/// reabre.
Stream<T> shareLatest<T>(Stream<T> Function() source) {
  final List<MultiStreamController<T>> listeners = <MultiStreamController<T>>[];
  StreamSubscription<T>? subscription;
  T? latest;
  bool hasLatest = false;

  void reset() {
    subscription = null;
    latest = null;
    hasLatest = false;
  }

  return Stream<T>.multi((MultiStreamController<T> controller) {
    listeners.add(controller);
    if (hasLatest) controller.add(latest as T);
    subscription ??= source().listen(
      (T value) {
        latest = value;
        hasLatest = true;
        for (final MultiStreamController<T> l
            in List<MultiStreamController<T>>.of(listeners)) {
          l.add(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final MultiStreamController<T> l
            in List<MultiStreamController<T>>.of(listeners)) {
          l.addError(error, stackTrace);
        }
      },
      onDone: () {
        final List<MultiStreamController<T>> done =
            List<MultiStreamController<T>>.of(listeners);
        listeners.clear();
        reset();
        for (final MultiStreamController<T> l in done) {
          l.close();
        }
      },
    );
    controller.onCancel = () {
      // Un oyente que ya no está (se cerró con la fuente) no puede cancelar la
      // suscripción que haya abierto otro después.
      if (!listeners.remove(controller)) return null;
      if (listeners.isNotEmpty) return null;
      final StreamSubscription<T>? current = subscription;
      reset();
      return current?.cancel();
    };
  }, isBroadcast: true);
}
