import 'package:image_picker/image_picker.dart';

import 'story.dart';

/// Reglas del compositor de historias, separadas de la pantalla porque la
/// pantalla necesita cámara y galería reales y no se puede montar en un test.
///
/// El compositor sustituye al editor anterior (superposiciones de texto,
/// pegatinas, recorte de vídeo, selección de portada): se elige el medio y se
/// publica. Lo que se quitó fue la EDICIÓN, no el vídeo.

/// Qué está haciendo el compositor. La galería no es otra pantalla: es la misma,
/// con el carrete subido por encima de la cámara (como Instagram).
enum StoryComposerMode { camera, gallery }

/// Tope de duración del vídeo. Sin editor ya no hay recorte, así que un vídeo
/// más largo se RECHAZA con un motivo en vez de cortarse por su cuenta: cortar
/// en silencio publicaría algo que la persona no eligió.
const Duration kStoryMaxVideoDuration = Duration(seconds: 15);

/// Lo que dura una historia de foto en el visor.
const int kStoryPhotoSeconds = 5;

/// Por qué no se puede publicar algo. `null` = se puede.
enum StoryMediaRejection {
  /// Vídeo por encima de [kStoryMaxVideoDuration].
  videoTooLong,

  /// El carrete devolvió un fichero que ya no existe (se borró mientras tanto,
  /// o es un asset de iCloud que no llegó a descargarse).
  unavailable,
}

/// ¿Se puede publicar esto?
///
/// `videoDuration` es null para fotos. Un vídeo sin duración conocida se deja
/// pasar: el backend tiene su propio límite y es preferible a bloquear una
/// publicación legítima porque el sistema no supo leer los metadatos.
StoryMediaRejection? checkStoryMedia({
  required StoryMediaType type,
  Duration? videoDuration,
  bool fileExists = true,
}) {
  if (!fileExists) return StoryMediaRejection.unavailable;
  if (type != StoryMediaType.video) return null;
  if (videoDuration == null) return null;
  return videoDuration > kStoryMaxVideoDuration
      ? StoryMediaRejection.videoTooLong
      : null;
}

/// Mensaje para la persona. En segunda persona y diciendo qué hacer, porque sin
/// editor no puede arreglarlo dentro de la app.
String storyRejectionMessage(StoryMediaRejection rejection) {
  switch (rejection) {
    case StoryMediaRejection.videoTooLong:
      final int max = kStoryMaxVideoDuration.inSeconds;
      return 'El vídeo dura más de $max segundos. Recórtalo en tu galería y '
          'vuelve a elegirlo.';
    case StoryMediaRejection.unavailable:
      return 'No hemos podido abrir ese archivo. Puede que se haya borrado o '
          'que aún se esté descargando de la nube.';
  }
}

/// Cuántos segundos se le pasan a `createStory`.
int storyDurationSeconds({
  required StoryMediaType type,
  Duration? videoDuration,
}) {
  if (type != StoryMediaType.video) return kStoryPhotoSeconds;
  final int seconds = (videoDuration ?? kStoryMaxVideoDuration).inSeconds;
  // Un vídeo de 0 s (metadatos raros) dejaría la historia pasando de largo sin
  // que se vea nada.
  return seconds.clamp(1, kStoryMaxVideoDuration.inSeconds);
}

/// Medio ya elegido y validado, listo para publicar.
class StoryDraft {
  const StoryDraft({
    required this.file,
    required this.type,
    this.videoDuration,
  });

  final XFile file;
  final StoryMediaType type;
  final Duration? videoDuration;

  int get durationSeconds =>
      storyDurationSeconds(type: type, videoDuration: videoDuration);
}
