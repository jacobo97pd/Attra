import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../domain/story.dart';
import 'story_repository.dart';

class StoryServiceException implements Exception {
  const StoryServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'StoryServiceException($code): $message';
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

class _ProcessedStoryImage {
  const _ProcessedStoryImage(this.bytes);
  final Uint8List bytes;
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

  bool get needsNativeProcessing {
    final double source = sourceDurationSeconds;
    final bool trimsStart = trimStartSeconds > 0.05;
    final bool trimsEnd =
        source > 0 && trimEndSeconds > 0 && trimEndSeconds < source - 0.05;
    return muted || trimsStart || trimsEnd;
  }
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

  static const int _maxImageDimension = 1920;

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
      final _ProcessedStoryImage processed =
          _processImage(await media.readAsBytes(), imageEdit);
      imagePath = 'stories/$uid/$storyId/image.jpg';
      thumbnailPath = imagePath;
      imageUrl = await _upload(imagePath, processed.bytes, 'image/jpeg');
      thumbnailUrl = imageUrl;
    } else {
      Uint8List videoBytes;
      String videoContentType = media.mimeType ?? 'video/mp4';
      Uint8List? thumbBytes;

      if (kIsWeb) {
        if (videoEdit.needsNativeProcessing) {
          throw const StoryServiceException(
            'La edicion de video no esta disponible en web.',
          );
        }
        videoBytes = await media.readAsBytes();
      } else {
        try {
          final MediaInfo? info = await VideoCompress.compressVideo(
            media.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            startTime: videoEdit.startSeconds,
            duration: videoEdit.durationSeconds(durationSeconds),
            includeAudio: !videoEdit.muted,
          );
          final String path = info?.path ?? media.path;
          videoBytes = await XFile(path).readAsBytes();
          videoContentType = 'video/mp4';
          thumbBytes = await VideoCompress.getByteThumbnail(
            media.path,
            quality: 50,
            position: videoEdit.thumbnailPositionMs,
          );
        } catch (e) {
          if (videoEdit.needsNativeProcessing) {
            throw StoryServiceException(
              'No se pudo procesar el video editado: $e',
            );
          }
          videoBytes = await media.readAsBytes();
        }
      }

      videoPath = 'stories/$uid/$storyId/video.mp4';
      thumbnailPath = 'stories/$uid/$storyId/thumb.jpg';
      videoUrl = await _upload(videoPath, videoBytes, videoContentType);
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
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

  _ProcessedStoryImage _processImage(Uint8List bytes, StoryImageEdit edit) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const StoryServiceException('No se pudo procesar la imagen.');
    }

    img.Image out = img.bakeOrientation(decoded);
    final int turns = edit.normalizedRotationTurns;
    if (turns != 0) {
      out = img.copyRotate(out, angle: turns * 90);
    }
    out = _cropImage(out, edit.normalizedCropZoom);
    out = _applyImageFilter(out, edit.filter);

    final int longest = out.width > out.height ? out.width : out.height;
    if (longest > _maxImageDimension) {
      out = out.width >= out.height
          ? img.copyResize(out, width: _maxImageDimension)
          : img.copyResize(out, height: _maxImageDimension);
    }
    return _ProcessedStoryImage(
      Uint8List.fromList(img.encodeJpg(out, quality: 85)),
    );
  }

  img.Image _cropImage(img.Image source, double zoom) {
    if (zoom <= 1.01) return source;
    final int width =
        (source.width / zoom).round().clamp(1, source.width).toInt();
    final int height =
        (source.height / zoom).round().clamp(1, source.height).toInt();
    final int x = ((source.width - width) / 2).round();
    final int y = ((source.height - height) / 2).round();
    return img.copyCrop(source, x: x, y: y, width: width, height: height);
  }

  img.Image _applyImageFilter(img.Image source, StoryImageFilter filter) {
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
