import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../domain/story.dart';
import '../domain/story_errors.dart';
import 'story_repository.dart';

/// Fallo del servicio de historias con texto TÉCNICO.
///
/// NO implementa [StoryUserFacingError] a propósito: marcar la clase entera como
/// presentable declaraba "buenos para enseñar" mensajes que son un volcado, como
/// `Error al subir: storage/retry-limit-exceeded - Max retry time exceeded` o el
/// `INTERNAL` en inglés de una función. Esos caen en el genérico y el detalle se
/// queda en los logs. Lo que sí se enseña va en [StoryUserMessageException].
class StoryServiceException implements Exception {
  const StoryServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'StoryServiceException($code): $message';
}

/// Fallo con un texto ESCRITO PARA LA PERSONA: dice qué pasó y qué hacer.
class StoryUserMessageException extends StoryServiceException
    implements StoryUserFacingError {
  const StoryUserMessageException(super.message, {this.detail});

  /// Volcado técnico. Va aparte del [message] para que acabe en los logs y no en
  /// la cara de la persona.
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StoryUserMessageException: $message'
      : 'StoryUserMessageException: $message ($detail)';
}

class StoryReplyResult {
  const StoryReplyResult({
    required this.outcome,
    this.chatId,
    this.chargedAttra = false,
  });

  /// message | matched | liked | insufficient_attras
  final String outcome;
  final String? chatId;

  /// La respuesta salió como Attra pagado. No coincide siempre con lo que pidió
  /// la UI: la estrella sobre alguien con quien ya hay chat solo manda un
  /// mensaje y no cuesta nada, así que no se puede anunciar "Attra enviado".
  final bool chargedAttra;

  bool get isMatch => outcome == 'matched';

  /// El Attra NO se envió: el monedero estaba a cero. El backend no degrada a
  /// like normal en silencio, así que aquí no se ha registrado nada.
  bool get insufficientAttras => outcome == 'insufficient_attras';

  /// `chargedAttra` se lee estricto (`== true`): un backend antiguo que no lo
  /// mande no puede acabar anunciando un Attra que nadie ha cobrado.
  factory StoryReplyResult.fromMap(Map<String, dynamic> map) {
    return StoryReplyResult(
      outcome: (map['outcome'] as String?) ?? 'liked',
      chatId: map['chatId'] as String?,
      chargedAttra: map['chargedAttra'] == true,
    );
  }
}

enum StoryImageFilter {
  none('Normal'),
  warm('Calida'),
  cool('Fria'),
  mono('B/N'),
  punch('Pop');

  const StoryImageFilter(this.label);
  final String label;
}

class StoryImageEdit {
  const StoryImageEdit({
    this.rotationTurns = 0,
    this.cropZoom = 1.0,
    this.filter = StoryImageFilter.none,
  });

  final int rotationTurns;
  final double cropZoom;
  final StoryImageFilter filter;

  int get normalizedRotationTurns => rotationTurns % 4;

  double get normalizedCropZoom => cropZoom.clamp(1.0, 2.5).toDouble();
}

class StoryVideoEdit {
  const StoryVideoEdit({
    this.sourceDurationSeconds = 0,
    this.trimStartSeconds = 0,
    this.trimEndSeconds = 0,
    this.coverPositionSeconds = 0,
    this.muted = false,
  });

  final double sourceDurationSeconds;
  final double trimStartSeconds;
  final double trimEndSeconds;
  final double coverPositionSeconds;
  final bool muted;

  int get startSeconds => trimStartSeconds.clamp(0.0, 3600.0).floor();

  int durationSeconds(int fallback) {
    final double source = max(
      1.0,
      sourceDurationSeconds > 0 ? sourceDurationSeconds : fallback.toDouble(),
    );
    final double start =
        startSeconds.toDouble().clamp(0.0, max(0.0, source - 1.0)).toDouble();
    final double end = (trimEndSeconds > 0 ? trimEndSeconds : source)
        .clamp(start + 1.0, source)
        .toDouble();
    return (end - start).round().clamp(1, 15).toInt();
  }

  int get thumbnailPositionMs {
    return (coverPositionSeconds.clamp(0.0, 3600.0) * 1000).round();
  }

  /// ¿Se recorta algo de verdad?
  ///
  /// Importa mucho más de lo que parece: el plugin de Android construye un
  /// `TrimDataSource(source, startTime, duration)` en cuanto se le pasa
  /// CUALQUIERA de los dos, y el tercer parámetro de la librería no es una
  /// duración sino el recorte contado DESDE EL FINAL (`trimEndUs`). Mandarle la
  /// duración entera con start=0 le sale `start + end >= duración` y lanza, el
  /// transcodificado se cancela y el plugin devuelve null: se acababa subiendo
  /// el vídeo del carrete tal cual, sin comprimir. Sin recorte no se le pasa
  /// ninguno de los dos y Android sí comprime.
  bool get trimsTimeline {
    final double source = sourceDurationSeconds;
    final bool trimsStart = trimStartSeconds > 0.05;
    final bool trimsEnd =
        source > 0 && trimEndSeconds > 0 && trimEndSeconds < source - 0.05;
    return trimsStart || trimsEnd;
  }

  bool get needsNativeProcessing => muted || trimsTimeline;
}

class StoryService {
  StoryService({
    required StoryRepository repository,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  })  : _repository = repository,
        _functions = functions,
        _storage = storage;

  final StoryRepository _repository;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  Future<bool> storiesEnabled() => _repository.storiesEnabled();

  Stream<List<Story>> observeLiveStories({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) =>
      _repository.observeLiveStories(
        excludeUid: excludeUid,
        excludedOwners: excludedOwners,
      );

  Stream<Story?> observeMyLiveStory(String uid) =>
      _repository.observeMyLiveStory(uid);

  /// Stories vivas agrupadas por dueño (para el muro apilado de Discover).
  Stream<Map<String, List<Story>>> observeLiveStoriesByOwner({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) =>
      _repository.observeLiveStoriesByOwner(
        excludeUid: excludeUid,
        excludedOwners: excludedOwners,
      );

  /// Todas las stories vivas del propio usuario (hasta el máximo permitido).
  Stream<List<Story>> observeMyLiveStories(String uid) =>
      _repository.observeMyLiveStories(uid);

  /// Máximo de historias vivas por usuario. Debe coincidir con
  /// MAX_ACTIVE_STORIES de functions/src/stories.ts: el servidor es quien manda,
  /// esto solo evita que la UI ofrezca subir una que se va a rechazar.
  static const int maxActiveStories = 5;

  Stream<Story?> observeStoryById(String id) =>
      _repository.observeStoryById(id);

  Future<String> createStory({
    required String uid,
    required XFile media,
    required StoryMediaType mediaType,
    required int durationSeconds,
    String caption = '',
    double captionX = 0.5,
    double captionY = 0.85,
    List<StoryOverlay> overlays = const <StoryOverlay>[],
    StoryImageEdit imageEdit = const StoryImageEdit(),
    StoryVideoEdit videoEdit = const StoryVideoEdit(),
    StoryVisibility visibility = StoryVisibility.discovery,
  }) async {
    final String storyId = _genId();
    String videoPath = '';
    String videoUrl = '';
    String imagePath = '';
    String imageUrl = '';
    String thumbnailPath = '';
    String thumbnailUrl = '';

    if (mediaType == StoryMediaType.image) {
      final Uint8List processed = processStoryImageBytes(
        await media.readAsBytes(),
        edit: imageEdit,
      );
      imagePath = 'stories/$uid/$storyId/image.jpg';
      thumbnailPath = imagePath;
      imageUrl = await _upload(imagePath, processed, 'image/jpeg');
      thumbnailUrl = imageUrl;
    } else {
      Uint8List videoBytes;
      String videoContentType = media.mimeType ?? 'video/mp4';
      Uint8List? thumbBytes;

      if (kIsWeb) {
        if (videoEdit.needsNativeProcessing) {
          throw const StoryUserMessageException(
            'La edición de vídeo no está disponible en la versión web.',
          );
        }
        videoBytes = await media.readAsBytes();
      } else {
        final bool trims = videoEdit.trimsTimeline;
        try {
          final MediaInfo? info = await VideoCompress.compressVideo(
            media.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            // Sin recorte NO se manda ninguno de los dos: ver `trimsTimeline`.
            // Mandarlos "por completar" hacía que en Android la compresión no
            // llegara a ejecutarse nunca y se subiera el original del carrete.
            startTime: trims ? videoEdit.startSeconds : null,
            duration: trims ? videoEdit.durationSeconds(durationSeconds) : null,
            includeAudio: !videoEdit.muted,
          );
          final String path = info?.path ?? media.path;
          videoBytes = await XFile(path).readAsBytes();
          videoContentType = 'video/mp4';
        } catch (e) {
          if (videoEdit.needsNativeProcessing) {
            throw StoryUserMessageException(
              'No hemos podido preparar ese vídeo. Vuelve a intentarlo o elige '
              'otro.',
              detail: '$e',
            );
          }
          videoBytes = await media.readAsBytes();
        }
        try {
          thumbBytes = await VideoCompress.getByteThumbnail(
            media.path,
            quality: 50,
            position: videoEdit.thumbnailPositionMs,
          );
        } catch (_) {
          // La miniatura va en su PROPIO try: compartiéndolo con la compresión,
          // que fallara al sacar la portada tiraba el vídeo ya comprimido y
          // subía el original en su lugar. Sin portada se publica igual.
        }
      }

      videoPath = 'stories/$uid/$storyId/video.mp4';
      videoUrl = await _upload(videoPath, videoBytes, videoContentType);
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        // La ruta solo se anuncia si de verdad se ha subido algo: si no, la
        // historia quedaba apuntando a un objeto que no existe.
        thumbnailPath = 'stories/$uid/$storyId/thumb.jpg';
        thumbnailUrl = await _upload(thumbnailPath, thumbBytes, 'image/jpeg');
      }
    }

    await _call('createStory', <String, dynamic>{
      'storyId': storyId,
      'mediaType': mediaType.wireName,
      'videoPath': videoPath,
      'videoUrl': videoUrl,
      'imagePath': imagePath,
      'imageUrl': imageUrl,
      'thumbnailPath': thumbnailPath,
      'thumbnailUrl': thumbnailUrl,
      'caption': caption,
      'captionX': captionX,
      'captionY': captionY,
      'overlays':
          overlays.map((StoryOverlay overlay) => overlay.toMap()).toList(),
      'visibility': visibility.wireName,
      'durationSeconds': durationSeconds,
    });
    return storyId;
  }

  Future<void> viewStory(String storyId) async {
    await _call('viewStory', <String, dynamic>{'storyId': storyId});
  }

  Future<StoryReplyResult> replyToStory(
    String storyId, {
    String text = '',
    bool asAttra = false,
  }) async {
    final Map<String, dynamic> data =
        await _call('replyToStory', <String, dynamic>{
      'storyId': storyId,
      'text': text,
      'asAttra': asAttra,
    });
    return StoryReplyResult.fromMap(data);
  }

  Future<void> deleteStory(String storyId) async {
    await _call('deleteStory', <String, dynamic>{'storyId': storyId});
  }

  Future<String> _upload(
      String path, Uint8List bytes, String contentType) async {
    try {
      final Reference ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw StoryServiceException(
        'Error al subir: ${e.code}${e.message != null ? ' - ${e.message}' : ''}',
        code: e.code,
      );
    }
  }


  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw StoryServiceException(e.message ?? e.code, code: e.code);
    }
  }

  String _genId() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final Random rng = Random();
    final String a = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    final String b = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    return '${ts}_$a$b';
  }
}

// ---------------------------------------------------------------------------
// Procesado de la foto
//
// De primer nivel y público a propósito: `createStory` necesita Firestore,
// Functions y Storage, así que dentro de la clase esto no se podía probar con
// bytes de verdad y la única prueba posible del mensaje de "foto ilegible" era
// una copia del texto escrita a mano, que seguiría en verde aunque el servicio
// volviera al mensaje mudo de antes.
// ---------------------------------------------------------------------------

/// Lado mayor máximo de la foto que se publica (px).
const int _maxStoryImageDimension = 1920;

/// Texto único del "no se puede leer esta foto".
///
/// Es una constante y no un literal suelto para que la prueba pueda mirar EL
/// mensaje que se enseña de verdad, y no una copia escrita a mano que seguiría
/// en verde aunque alguien devolviera el "No se pudo procesar la imagen."
const String storyUnreadableImageMessage =
    'No hemos podido leer esta foto: puede estar dañada o en un formato que '
    'no reconocemos. Prueba con otra, o haz una captura de pantalla de esta '
    'y publica esa.';

/// Deja la foto lista para subir: orientación, edición, tope de 1920 px, sin
/// metadatos y en JPEG.
///
/// Lanza [StoryUserMessageException] con [storyUnreadableImageMessage] si no hay
/// manera de leer los bytes.
Uint8List processStoryImageBytes(
  Uint8List bytes, {
  StoryImageEdit edit = const StoryImageEdit(),
}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (e) {
    // `decodeImage` NO siempre devuelve null ante un fichero que no puede
    // leer: los decodificadores de PNG, JPEG y TIFF LANZAN ImageException con
    // datos truncados o comprimidos de una forma que no soportan (un JPEG a
    // medio bajar de iCloud, por ejemplo). Sin este catch la excepción subía
    // hasta el compositor, no la reconocía como presentable y se enseñaba
    // "Revisa tu conexión": un problema permanente de fichero disfrazado de
    // fallo de red, con la persona reintentando en bucle.
    throw StoryUserMessageException(storyUnreadableImageMessage, detail: '$e');
  }
  if (decoded == null) {
    // El caso habitual era HEIC de la cámara del iPhone, y de eso ya se
    // encarga el carrete antes de llegar aquí (ver StoryImageConverter). Si
    // aun así no se puede decodificar, el fichero está dañado o es un formato
    // que no lee nadie: hay que decir qué pasa y qué se puede hacer, porque el
    // mensaje anterior ("No se pudo procesar la imagen") dejaba a la persona
    // sin nada que intentar.
    throw const StoryUserMessageException(storyUnreadableImageMessage);
  }

  img.Image out = img.bakeOrientation(decoded);
  final int turns = edit.normalizedRotationTurns;
  if (turns != 0) {
    out = img.copyRotate(out, angle: turns * 90);
  }
  out = _cropStoryImage(out, edit.normalizedCropZoom);
  out = _applyStoryFilter(out, edit.filter);

  final int longest = out.width > out.height ? out.width : out.height;
  if (longest > _maxStoryImageDimension) {
    // `interpolation` explícito: el valor por defecto de `copyResize` es
    // `nearest`, que al reducir tira filas y columnas sin promediar y deja
    // dentado y moiré en el pelo, las pestañas y los tejidos de rayas.
    out = out.width >= out.height
        ? img.copyResize(
            out,
            width: _maxStoryImageDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            out,
            height: _maxStoryImageDimension,
            interpolation: img.Interpolation.average,
          );
  }
  // Fuera los metadatos ANTES de codificar: `encodeJpg` reescribe el EXIF que
  // traía la foto, y en el carrete eso incluye las coordenadas GPS de dónde se
  // hizo. Una historia es pública, así que publicarla no puede publicar
  // también la casa de quien la sube.
  out.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

img.Image _cropStoryImage(img.Image source, double zoom) {
  if (zoom <= 1.01) return source;
  final int width =
      (source.width / zoom).round().clamp(1, source.width).toInt();
  final int height =
      (source.height / zoom).round().clamp(1, source.height).toInt();
  final int x = ((source.width - width) / 2).round();
  final int y = ((source.height - height) / 2).round();
  return img.copyCrop(source, x: x, y: y, width: width, height: height);
}

img.Image _applyStoryFilter(img.Image source, StoryImageFilter filter) {
  return switch (filter) {
    StoryImageFilter.none => source,
    StoryImageFilter.warm => img.adjustColor(
        source,
        brightness: 1.04,
        contrast: 1.04,
        saturation: 1.12,
        hue: 7,
      ),
    StoryImageFilter.cool => img.adjustColor(
        source,
        brightness: 1.02,
        contrast: 1.03,
        saturation: 0.98,
        hue: -8,
      ),
    StoryImageFilter.mono => img.grayscale(source),
    StoryImageFilter.punch => img.adjustColor(
        source,
        brightness: 1.04,
        contrast: 1.16,
        saturation: 1.24,
      ),
  };
}
