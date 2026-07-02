import 'package:attra/src/features/stories/domain/story.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Story _story({
  required String status,
  required DateTime expiresAt,
}) {
  return Story.fromMap('s1', <String, dynamic>{
    'ownerUid': 'u1',
    'displayName': 'Bella',
    'mediaType': 'video',
    'videoPath': 'stories/u1/s1/video.mp4',
    'videoUrl': 'https://x/v.mp4',
    'status': status,
    'visibility': 'discovery',
    'durationSeconds': 8,
    'createdAt': Timestamp.now(),
    'expiresAt': Timestamp.fromDate(expiresAt),
  });
}

void main() {
  group('Story.isLive', () {
    final DateTime future = DateTime.now().add(const Duration(hours: 5));
    final DateTime past = DateTime.now().subtract(const Duration(hours: 1));

    test('active y no caducada => viva', () {
      expect(_story(status: 'active', expiresAt: future).isLive, isTrue);
    });

    test('active pero caducada (expiresAt<now) => NO aparece', () {
      expect(_story(status: 'active', expiresAt: past).isLive, isFalse);
    });

    test('status expired => NO aparece aunque no haya pasado el tiempo', () {
      expect(_story(status: 'expired', expiresAt: future).isLive, isFalse);
    });

    test('status deleted => NO aparece', () {
      expect(_story(status: 'deleted', expiresAt: future).isLive, isFalse);
    });
  });

  group('Story.fromMap', () {
    test('parsea campos y enums', () {
      final Story s = _story(
          status: 'active',
          expiresAt: DateTime.now().add(const Duration(hours: 1)));
      expect(s.ownerUid, 'u1');
      expect(s.displayName, 'Bella');
      expect(s.visibility, StoryVisibility.discovery);
      expect(s.mediaType, StoryMediaType.video);
      expect(s.isVideo, isTrue);
      expect(s.durationSeconds, 8);
      expect(s.videoUrl, 'https://x/v.mp4');
      expect(s.previewUrl, '');
    });

    test('status desconocido cae a active', () {
      expect(StoryStatus.fromValue('???'), StoryStatus.active);
      expect(StoryVisibility.fromValue('???'), StoryVisibility.discovery);
      expect(StoryMediaType.fromValue('???'), StoryMediaType.video);
    });

    test('parsea story de foto', () {
      final Story s = Story.fromMap('s2', <String, dynamic>{
        'ownerUid': 'u1',
        'displayName': 'Bella',
        'mediaType': 'image',
        'imagePath': 'stories/u1/s2/image.jpg',
        'imageUrl': 'https://x/i.jpg',
        'thumbnailUrl': 'https://x/i.jpg',
        'status': 'active',
        'visibility': 'matches',
        'durationSeconds': 5,
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      });

      expect(s.mediaType, StoryMediaType.image);
      expect(s.isImage, isTrue);
      expect(s.visibility, StoryVisibility.matches);
      expect(s.imageUrl, 'https://x/i.jpg');
      expect(s.previewUrl, 'https://x/i.jpg');
    });

    test('parsea overlays de editor', () {
      final Story s = Story.fromMap('s3', <String, dynamic>{
        'ownerUid': 'u1',
        'displayName': 'Bella',
        'mediaType': 'image',
        'imageUrl': 'https://x/i.jpg',
        'status': 'active',
        'visibility': 'discovery',
        'overlays': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'text': 'Hola',
            'x': 0.2,
            'y': 0.3,
            'scale': 1.4,
            'rotation': 0.25,
            'color': 0xFFFFC857,
            'background': true,
            'align': 'left',
          },
          <String, dynamic>{
            'type': 'sticker',
            'text': '🔥',
            'x': 0.7,
            'y': 0.6,
          },
        ],
      });

      expect(s.visualOverlays, hasLength(2));
      expect(s.visualOverlays.first.type, StoryOverlayType.text);
      expect(s.visualOverlays.first.text, 'Hola');
      expect(s.visualOverlays.first.background, isTrue);
      expect(s.visualOverlays.first.align, StoryOverlayAlign.left);
      expect(s.visualOverlays.last.type, StoryOverlayType.sticker);
    });

    test('caption antiguo se expone como overlay visual', () {
      final Story s = Story.fromMap('s4', <String, dynamic>{
        'ownerUid': 'u1',
        'displayName': 'Bella',
        'videoUrl': 'https://x/v.mp4',
        'caption': 'Legacy',
        'captionX': 0.4,
        'captionY': 0.8,
        'status': 'active',
        'visibility': 'discovery',
      });

      expect(s.overlays, isEmpty);
      expect(s.visualOverlays, hasLength(1));
      expect(s.visualOverlays.single.text, 'Legacy');
      expect(s.visualOverlays.single.x, 0.4);
      expect(s.visualOverlays.single.y, 0.8);
    });
  });
}
