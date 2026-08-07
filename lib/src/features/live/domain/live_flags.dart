/// Feed en vivo — configuración remota (`config/featureFlags` →
/// `MonetizationFeatureFlags.rawConfig`). Mismo patrón que [SafeDateFlags]:
/// claves `feature_live_*` con DEFAULTS LOCALES SEGUROS (todo OFF).
///
/// PORQUÉ dark launch y no un despliegue normal: esto es vídeo 1:1 en directo
/// con desconocidos, exactamente el terreno por el que Apple ya rechazó la app
/// una vez (guideline 1.2, contenido generado por usuarios). Con la flag
/// apagada NO existe ni el punto de entrada, así que la build que se sube a
/// revisión se comporta como si la función no estuviera.
///
/// Regla de oro: si Remote Config no carga, el directo queda DESACTIVADO.
library;

class LiveFlags {
  const LiveFlags({
    this.enabled = false,
    this.killSwitch = false,
  });

  /// Master switch. Si `false`, el directo no aparece por ningún sitio y la app
  /// va EXACTAMENTE como antes.
  final bool enabled;

  /// Apagado en caliente aunque [enabled] siga a `true`.
  ///
  /// PORQUÉ separado del master switch: cuando haya que cortar por un pico de
  /// abuso o una petición de revisión, hay que poder hacerlo sin borrar la
  /// configuración de lanzamiento (y sin publicar una versión). Volver a
  /// encender es entonces un solo campo, no reconstruir el estado anterior.
  final bool killSwitch;

  /// Único getter que debe consultar la UI: activado y sin corte de emergencia.
  bool get active => enabled && !killSwitch;

  factory LiveFlags.fromMap(Map<String, dynamic> map) {
    bool b(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    return LiveFlags(
      enabled: b('feature_live_enabled', false),
      killSwitch: b('feature_live_kill_switch', false),
    );
  }

  /// Fallback seguro (OFF) cuando no hay config remota disponible.
  static const LiveFlags disabled = LiveFlags();
}
