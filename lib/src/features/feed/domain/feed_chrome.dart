/// Cuándo esconder la "carrocería" del feed (filtros arriba, navegación abajo)
/// mientras se lee una ficha, al estilo Hinge: bajar por un perfil la esconde
/// para dejar sitio a las fotos y subir la devuelve.
///
/// Va aparte de la pantalla porque la decisión tiene trampas que conviene fijar
/// con tests y no redescubrir a mano:
/// - un arrastre lento mueve 1-2 px por frame, así que se ACUMULA el recorrido
///   en una misma dirección en vez de mirar cada frame suelto;
/// - arriba del todo la carrocería siempre se ve, aunque el último gesto fuera
///   hacia abajo: si no, podía quedarse escondida sin forma de recuperarla;
/// - el rebote de iOS al pasarse del final hace "subir" el contenido sin que
///   nadie haya subido, y eso no debe devolver la carrocería.
class FeedChromeTracker {
  FeedChromeTracker({this.threshold = 12, this.topSlack = 8});

  /// Recorrido (px) en una misma dirección necesario para cambiar de estado.
  final double threshold;

  /// Por debajo de este desplazamiento se considera "arriba del todo".
  final double topSlack;

  double _drift = 0;

  /// Olvida el recorrido acumulado (al cambiar de ficha).
  void reset() => _drift = 0;

  /// Procesa un desplazamiento vertical de la ficha.
  ///
  /// [delta] > 0 es bajar por el perfil. Devuelve `true` si hay que esconder,
  /// `false` si hay que mostrar y `null` si no cambia nada.
  bool? update({
    required double pixels,
    required double minExtent,
    required double maxExtent,
    required double delta,
  }) {
    if (pixels - minExtent <= topSlack) {
      _drift = 0;
      return false;
    }
    // Pasado el final solo puede ser el rebote: el contenido vuelve atrás solo.
    if (pixels >= maxExtent) return null;
    if (delta == 0) return null;
    if ((delta > 0) != (_drift > 0)) _drift = 0;
    _drift += delta;
    if (_drift >= threshold) return true;
    if (_drift <= -threshold) return false;
    return null;
  }
}
