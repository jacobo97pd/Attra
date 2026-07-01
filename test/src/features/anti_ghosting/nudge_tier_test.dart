import 'package:attra/src/features/anti_ghosting/domain/nudge_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NudgeTier (Attra Clear §5)', () {
    test('umbrales por horas', () {
      expect(nudgeTierForHours(0), NudgeTier.none);
      expect(nudgeTierForHours(17), NudgeTier.none);
      expect(nudgeTierForHours(18), NudgeTier.gentle);
      expect(nudgeTierForHours(47), NudgeTier.gentle);
      expect(nudgeTierForHours(48), NudgeTier.firm);
      expect(nudgeTierForHours(95), NudgeTier.firm);
      expect(nudgeTierForHours(96), NudgeTier.cold);
      expect(nudgeTierForHours(500), NudgeTier.cold);
    });

    test('negativo => none', () {
      expect(nudgeTierForHours(-5), NudgeTier.none);
    });

    test('desde Duration', () {
      expect(nudgeTierForDuration(const Duration(hours: 18)), NudgeTier.gentle);
      expect(nudgeTierForDuration(const Duration(hours: 49)), NudgeTier.firm);
      expect(nudgeTierForDuration(const Duration(hours: 100)), NudgeTier.cold);
      expect(nudgeTierForDuration(const Duration(minutes: 30)), NudgeTier.none);
    });

    test('isActive', () {
      expect(NudgeTier.none.isActive, isFalse);
      expect(NudgeTier.gentle.isActive, isTrue);
      expect(NudgeTier.firm.isActive, isTrue);
      expect(NudgeTier.cold.isActive, isTrue);
    });
  });
}
