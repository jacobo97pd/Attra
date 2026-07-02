import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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

/// Resultado de responder a una story.
class StoryReplyResult {
  const StoryReplyResult({required this.outcome, this.chatId});
  final String outcome; // message | matched | liked
  final String? chatId;
  bool get isMatch => outcome == 'matched';
}

/// Fachada de stories: crear (comprime en móvil, sube tal cual en web) +
/// ver/responder/borrar via Cloud Functions + lecturas via StoryRepository.
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

  // --- Lecturas + flag ---
  Future<bool> storiesEnabled() => _repository.storiesEnabled();
  Stream<List<Story>> observeLiveStories({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) =>
      _repository.observeLiveStories(
          excludeUid: excludeUid, excludedOwners: excludedOwners);
  Stream<Story?> observeMyLiveStory(String uid) =>
      _repository.observeMyLiveStory(uid);
  Stream<Story?> observeStoryById(String id) =>
      _repository.observeStoryById(id);

  // --- Escrituras ---

  /// Crea una story: comprime el vídeo (móvil) o lo sube tal cual (web),
  /// genera thumbnail (móvil), sube a Storage y crea el doc via `createStory`.
  Future<String> createStory({
    required String uid,
    required XFile video,
    required int durationSeconds,
    String caption = '',
    double captionX = 0.5,
    double captionY = 0.85,
    StoryVisibility visibility = StoryVisibility.discovery,
  }) async {
    final String storyId = _genId();
    Uint8List videoBytes;
    String videoContentType = video.mimeType ?? 'video/mp4';
    Uint8List? thumbBytes;

    if (kIsWeb) {
      videoBytes = await video.readAsBytes();
    } else {
      try {
        final MediaInfo? info = await VideoCompress.compressVideo(
          video.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        final String path = info?.path ?? video.path;
        videoBytes = await XFile(path).readAsBytes();
        videoContentType = 'video/mp4';
        thumbBytes = await VideoCompress.getByteThumbnail(video.path,
            quality: 50, position: -1);
      } catch (_) {
        // Si la compresión falla, sube el original.
        videoBytes = await video.readAsBytes();
      }
    }

    final String videoPath = 'stories/$uid/$storyId/video.mp4';
    final String thumbPath = 'stories/$uid/$storyId/thumb.jpg';

    final String videoUrl =
        await _upload(videoPath, videoBytes, videoContentType);
    String thumbnailUrl = '';
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      thumbnailUrl = await _upload(thumbPath, thumbBytes, 'image/jpeg');
    }

    await _call('createStory', <String, dynamic>{
      'storyId': storyId,
      'videoPath': videoPath,
      'thumbnailPath': thumbPath,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'caption': caption,
      'captionX': captionX,
      'captionY': captionY,
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
    return StoryReplyResult(
      outcome: (data['outcome'] as String?) ?? 'liked',
      chatId: data['chatId'] as String?,
    );
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
          'Error al subir: ${e.code}${e.message != null ? ' — ${e.message}' : ''}',
          code: e.code);
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
