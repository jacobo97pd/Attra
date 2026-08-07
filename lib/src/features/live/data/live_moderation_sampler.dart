import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image/image.dart' as img;

import '../domain/live_constants.dart';
import 'live_service.dart';

/// Muestreador de fotogramas para moderación.
///
/// EL PUNTO CLAVE DEL SISTEMA ENTERO: cada cliente modera el vídeo que
/// RECIBE, nunca el que emite.
///
/// El vídeo va peer-to-peer, así que el servidor no lo ve jamás y la única
/// forma de moderarlo es desde un cliente. Si cada uno moderase su propia
/// cámara, un cliente modificado (un APK recompilado sin esta clase) tendría
/// barra libre: bastaría con no enviar nunca un fotograma. Moderando el flujo
/// AJENO, el infractor no controla al testigo: quien está delante suya es
/// quien manda las pruebas, y él no puede impedirlo.
///
/// De ahí también la contramedida del backend: un cliente que NO envía NINGÚN
/// fotograma durante toda la sesión es sospechoso (es exactamente lo que haría
/// el infractor para tapar al otro) y queda anotado. No se corta por eso: hay
/// móviles lentos y redes malas, y castigar por ausencia de pruebas
/// produciría falsos positivos.
class LiveModerationSampler {
  LiveModerationSampler({
    required LiveService service,
    required this.sessionId,
    required this.targetUid,
    required MediaStreamTrack? Function() remoteVideoTrack,
    this.onResult,
  })  : _service = service,
        _remoteVideoTrack = remoteVideoTrack;

  final LiveService _service;
  final String sessionId;

  /// A quién pertenece el vídeo que se está moderando (el OTRO, siempre).
  final String targetUid;

  /// Se resuelve en cada tick, no una vez: la pista remota puede aparecer
  /// después de arrancar el muestreo (o cambiar en una renegociación).
  final MediaStreamTrack? Function() _remoteVideoTrack;

  /// Veredicto del backend sobre cada fotograma. Si pide cortar, se corta.
  final void Function(LiveModerationResult result)? onResult;

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  /// Nº de fotogramas realmente enviados. Útil para diagnóstico y para que la
  /// UI pueda mostrar que la moderación está funcionando.
  int get sentFrames => _sentFrames;
  int _sentFrames = 0;

  /// Arranca el muestreo cada [LiveConstants.sampleInterval] (5 s).
  ///
  /// El primer disparo también espera 5 s: al principio de la llamada aún no
  /// hay medio remoto y capturar en seco solo generaría errores.
  void start() {
    if (_timer != null || _stopped) return;
    _timer = Timer.periodic(
      LiveConstants.sampleInterval,
      (_) => unawaited(_tick()),
    );
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    // Un solo envío en vuelo: si la red va lenta, encolar fotogramas solo
    // gastaría batería y datos para mandar imágenes ya viejas.
    if (_busy || _stopped) return;
    final MediaStreamTrack? track = _remoteVideoTrack();
    if (track == null) return;

    _busy = true;
    try {
      final ByteBuffer buffer = await track.captureFrame();
      if (_stopped) return;
      final Uint8List raw = buffer.asUint8List();
      if (raw.isEmpty) return;

      // Reescalado + JPEG en un ISOLATE: el PNG que devuelve captureFrame
      // puede pasar del megabyte y decodificarlo en el hilo de UI daría un
      // tirón visible en mitad de una videollamada. Además reduce ~20x el
      // payload de la callable y el coste por imagen de Vision.
      final String? encoded = await compute(_downscaleToJpegBase64, raw);
      if (encoded == null || encoded.isEmpty || _stopped) return;

      final LiveModerationResult result = await _service.reviewFrame(
        sessionId: sessionId,
        targetUid: targetUid,
        imageBase64: encoded,
      );
      _sentFrames++;
      if (_stopped) return;
      onResult?.call(result);
    } on LiveServiceException catch (error) {
      // Un fallo de moderación NO puede cortar la llamada por su cuenta: se
      // reintenta al siguiente tick. Cortar ante un error de red convertiría
      // una mala cobertura en una acusación.
      if (kDebugMode) debugPrint('[live] reviewLiveFrame falló: $error');
    } catch (error) {
      if (kDebugMode) debugPrint('[live] captura de fotograma falló: $error');
    } finally {
      _busy = false;
    }
  }
}

/// Ancho máximo del fotograma que se manda a moderar.
///
/// SafeSearch no necesita más para clasificar desnudez, y a 480 px el JPEG
/// baja a unas decenas de KB: cabe de sobra en el payload de una callable
/// (límite 10 MB) incluso con la sobrecarga de base64.
const int _kModerationWidth = 480;

/// Calidad JPEG. 70 conserva de sobra la señal que busca el clasificador y
/// evita mandar imágenes nítidas de gente por la red más de lo necesario.
const int _kModerationQuality = 70;

/// Ejecutado en un isolate por [compute]: PNG crudo -> JPEG reducido en base64.
///
/// Devuelve null si la imagen no se puede decodificar; es preferible saltarse
/// un fotograma que propagar una excepción desde el isolate.
String? _downscaleToJpegBase64(Uint8List pngBytes) {
  try {
    final img.Image? decoded = img.decodeImage(pngBytes);
    if (decoded == null) return null;
    final img.Image resized = decoded.width > _kModerationWidth
        ? img.copyResize(decoded, width: _kModerationWidth)
        : decoded;
    final Uint8List jpeg = img.encodeJpg(resized, quality: _kModerationQuality);
    return base64Encode(jpeg);
  } catch (_) {
    return null;
  }
}
