import 'package:attra/src/features/match/domain/like.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Like target story', () {
    test('parsea un like con targetType story + relatedStoryId', () {
      final Like like = Like.fromMap(<String, dynamic>{
        'fromUid': 'a',
        'toUid': 'b',
        'type': 'like',
        'status': 'active',
        'targetType': 'story',
        'relatedStoryId': 's1',
      });
      expect(like.targetType, LikeTargetType.story);
      expect(like.isStoryTarget, isTrue);
      expect(like.isPhotoTarget, isFalse);
      expect(like.relatedStoryId, 's1');
    });

    test('like de perfil clásico sigue funcionando (sin targetType)', () {
      final Like like = Like.fromMap(<String, dynamic>{
        'fromUid': 'a',
        'toUid': 'b',
        'type': 'like',
        'status': 'active',
      });
      expect(like.targetType, LikeTargetType.profile);
      expect(like.isStoryTarget, isFalse);
      expect(like.relatedStoryId, isNull);
    });

    test('parsea flags de prioridad premium con fallback seguro', () {
      final Like like = Like.fromMap(<String, dynamic>{
        'fromUid': 'a',
        'toUid': 'b',
        'type': 'like',
        'status': 'active',
        'senderIsPlus': true,
        'senderIsPro': false,
        'priorityReason': 'plus',
        'compatibilityScore': 0.75,
        'senderActivityScore': 0.5,
      });

      expect(like.senderIsPlus, isTrue);
      expect(like.senderIsPro, isFalse);
      expect(like.effectivePriorityReason, 'plus');
      expect(like.compatibilityScore, 0.75);
      expect(like.senderActivityScore, 0.5);
    });
  });
}
