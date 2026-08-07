import 'package:flutter_webrtc/flutter_webrtc.dart';

/// La cámara o el micrófono no están disponibles (permiso denegado, hardware
/// ocupado por otra app…). Se distingue del resto de errores porque la UI
/// tiene que ofrecer una salida concreta: explicar el porqué y llevar a
/// Ajustes, no un "algo ha fallado".
class LiveMediaException implements Exception {
  const LiveMediaException(this.message, {this.permissionDenied = false});

  final String message;

  /// El usuario dijo que no (o el sistema lo bloqueó). Reintentar sin pasar
  /// por Ajustes no serviría de nada.
  final bool permissionDenied;

  @override
  String toString() => 'LiveMediaException($message)';
}

/// Constraints del vídeo del directo.
///
/// 640x480 y 24 fps a propósito: en tres minutos de conversación cara a cara
/// más resolución no aporta nada y sí cuesta datos, batería y peso en los
/// fotogramas que se envían a moderar.
const Map<String, dynamic> kLiveMediaConstraints = <String, dynamic>{
  'audio': true,
  'video': <String, dynamic>{
    'facingMode': 'user',
    'width': <String, dynamic>{'ideal': 640},
    'height': <String, dynamic>{'ideal': 480},
    'frameRate': <String, dynamic>{'ideal': 24},
  },
};

/// Abre cámara y micrófono, traduciendo el fallo a [LiveMediaException].
///
/// Los SDK nativos devuelven textos distintos para lo mismo, así que
/// clasificamos por palabra clave en vez de por tipo de excepción: lo que
/// importa es distinguir "me han dicho que no" de "la cámara está ocupada",
/// porque la salida que se le ofrece al usuario es distinta.
Future<MediaStream> openLiveMedia() async {
  try {
    return await navigator.mediaDevices.getUserMedia(kLiveMediaConstraints);
  } catch (error) {
    final String raw = error.toString().toLowerCase();
    final bool denied = raw.contains('permission') ||
        raw.contains('denied') ||
        raw.contains('notallowed');
    throw LiveMediaException(
      denied
          ? 'Necesitamos cámara y micrófono para el vídeo en directo.'
          : 'No hemos podido abrir la cámara. Cierra otras apps que la estén '
              'usando e inténtalo otra vez.',
      permissionDenied: denied,
    );
  }
}

/// Cámara propia encendida ANTES de entrar en la cola.
///
/// PORQUÉ antes y no al emparejar: si el permiso se pidiera cuando ya hay
/// pareja, un "no" dejaría a la otra persona esperando un vídeo que nunca
/// llega y le habría gastado su turno. Pidiéndolo antes, quien no puede
/// emitir sencillamente no entra en la cola. De paso el usuario se ve a sí
/// mismo mientras espera, que es lo que espera de una videollamada y además
/// hace evidente que la cámara está encendida.
class LiveLocalPreview {
  LiveLocalPreview._(this.renderer, this._stream);

  final RTCVideoRenderer renderer;
  MediaStream? _stream;

  MediaStream? get stream => _stream;

  static Future<LiveLocalPreview> open() async {
    final RTCVideoRenderer renderer = RTCVideoRenderer();
    await renderer.initialize();
    try {
      final MediaStream stream = await openLiveMedia();
      renderer.srcObject = stream;
      return LiveLocalPreview._(renderer, stream);
    } catch (_) {
      // Sin medio no hay preview que enseñar: se libera la textura para no
      // dejarla colgando.
      await renderer.dispose();
      rethrow;
    }
  }

  /// Cede el stream a la videollamada.
  ///
  /// Se entrega el MISMO stream en vez de volver a abrir la cámara: reabrirla
  /// provoca un parpadeo del LED y, en algunos Android, un error de "cámara en
  /// uso" porque la anterior aún no se ha liberado. Tras ceder, esta clase ya
  /// NO es dueña del stream y no lo detendrá.
  MediaStream? release() {
    final MediaStream? handed = _stream;
    _stream = null;
    try {
      renderer.srcObject = null;
    } catch (_) {/* renderer sin inicializar */}
    return handed;
  }

  /// Apaga la preview. Si el stream no se cedió, se detiene de verdad: la
  /// cámara no puede quedarse encendida porque el usuario haya cancelado.
  Future<void> dispose() async {
    final MediaStream? owned = _stream;
    _stream = null;
    if (owned != null) {
      try {
        for (final MediaStreamTrack track in owned.getTracks()) {
          await track.stop();
        }
        await owned.dispose();
      } catch (_) {/* ya estaba cerrado */}
    }
    try {
      renderer.srcObject = null;
    } catch (_) {/* renderer sin inicializar */}
    try {
      await renderer.dispose();
    } catch (_) {/* renderer ya liberado */}
  }
}
