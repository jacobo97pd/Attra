import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Mantiene la pantalla encendida mientras hay directo.
///
/// PORQUÉ hace falta: el temporizador de inactividad del sistema no sabe que
/// estás en una videollamada —no hay toques en pantalla mientras hablas—, así
/// que la apagaba a la media. Al apagarse, la app pasa a `paused` y
/// `LiveController.handleAppBackgrounded()` corta la sesión: la llamada se caía
/// sola a mitad de conversación y para el otro parecía que le habían colgado.
///
/// PORQUÉ envuelto y no llamando a WakelockPlus directamente: es un plugin con
/// canal nativo. En `flutter test` no hay implementación y cualquier llamada
/// lanzaría `MissingPluginException`, tumbando tests de widget que no tienen
/// nada que ver. Aquí se traga el fallo: no poder mantener la pantalla
/// encendida NUNCA puede impedir una videollamada.
class LiveWakelock {
  LiveWakelock();

  bool _enabled = false;

  /// Estado que este objeto cree tener aplicado (para tests y para no repetir
  /// llamadas al canal en cada `notifyListeners`).
  bool get isEnabled => _enabled;

  /// Idempotente: se llama desde el listener del controlador, que dispara
  /// muchas veces por segundo mientras corre el contador.
  Future<void> update({required bool keepAwake}) async {
    if (keepAwake == _enabled) return;
    _enabled = keepAwake;
    await _apply(keepAwake);
  }

  /// Suelta el bloqueo pase lo que pase. Se llama en `dispose`: dejar la
  /// pantalla clavada encendida tras salir del directo se comería la batería
  /// sin que el usuario entendiera por qué.
  Future<void> release() => update(keepAwake: false);

  Future<void> _apply(bool value) async {
    // En web y escritorio no aplica (y el plugin no está implementado en todas
    // las plataformas de escritorio).
    if (kIsWeb) return;
    try {
      await WakelockPlus.toggle(enable: value);
    } catch (_) {
      // Sin plugin (tests) o plataforma no soportada.
    }
  }
}
