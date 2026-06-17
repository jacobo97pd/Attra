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
      expect(s.durationSeconds, 8);
      expect(s.videoUrl, 'https://x/v.mp4');
    });

    test('status desconocido cae a active', () {
      expect(StoryStatus.fromValue('???'), StoryStatus.active);
      expect(StoryVisibility.fromValue('???'), StoryVisibility.discovery);
    });
  });
}
