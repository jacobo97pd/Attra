import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoryImageEdit', () {
    test('normaliza rotacion y zoom de recorte', () {
      const StoryImageEdit edit = StoryImageEdit(
        rotationTurns: -1,
        cropZoom: 8,
        filter: StoryImageFilter.punch,
      );

      expect(edit.normalizedRotationTurns, 3);
      expect(edit.normalizedCropZoom, 2.5);
      expect(edit.filter, StoryImageFilter.punch);
    });
  });

  group('StoryVideoEdit', () {
    test('prepara recorte, mute y portada', () {
      const StoryVideoEdit edit = StoryVideoEdit(
        sourceDurationSeconds: 42,
        trimStartSeconds: 10.2,
        trimEndSeconds: 40,
        coverPositionSeconds: 12.3,
        muted: true,
      );

      expect(edit.startSeconds, 10);
      expect(edit.durationSeconds(15), 15);
      expect(edit.thumbnailPositionMs, 12300);
      expect(edit.needsNativeProcessing, isTrue);
    });
  });
}
