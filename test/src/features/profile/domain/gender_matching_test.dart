import 'package:attra/src/features/profile/domain/gender_matching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GenderMatching.wants', () {
    test('sin preferencia declarada no excluye a nadie', () {
      for (final String gender in <String>[
        'female',
        'male',
        'non_binary',
        'trans_woman',
        'trans_man',
        'genderfluid',
        'agender',
        'other',
        '',
      ]) {
        expect(
          GenderMatching.wants(const <String>[], gender),
          isTrue,
          reason: 'interestedIn vacío no debería excluir "$gender"',
        );
      }
    });

    test('sin género declarado no excluye', () {
      expect(GenderMatching.wants(const <String>['female'], ''), isTrue);
    });

    test('las tres casillas siguen coincidiendo consigo mismas', () {
      expect(GenderMatching.wants(const <String>['female'], 'female'), isTrue);
      expect(GenderMatching.wants(const <String>['male'], 'male'), isTrue);
      expect(
        GenderMatching.wants(const <String>['non_binary'], 'non_binary'),
        isTrue,
      );
    });

    test('una casilla no arrastra a las otras', () {
      expect(GenderMatching.wants(const <String>['female'], 'male'), isFalse);
      expect(GenderMatching.wants(const <String>['male'], 'female'), isFalse);
      expect(
        GenderMatching.wants(const <String>['female'], 'non_binary'),
        isFalse,
      );
    });

    // El fallo que arregla este archivo: estas cinco identidades no coincidían
    // con NADIE que hubiera dicho a quién busca.
    test('mujer trans entra en "Mujer", no en "Hombre"', () {
      expect(
        GenderMatching.wants(const <String>['female'], 'trans_woman'),
        isTrue,
      );
      expect(
        GenderMatching.wants(const <String>['male'], 'trans_woman'),
        isFalse,
      );
    });

    test('hombre trans entra en "Hombre", no en "Mujer"', () {
      expect(GenderMatching.wants(const <String>['male'], 'trans_man'), isTrue);
      expect(
        GenderMatching.wants(const <String>['female'], 'trans_man'),
        isFalse,
      );
    });

    test('género fluido y agénero entran en "No binario"', () {
      expect(
        GenderMatching.wants(const <String>['non_binary'], 'genderfluid'),
        isTrue,
      );
      expect(
        GenderMatching.wants(const <String>['non_binary'], 'agender'),
        isTrue,
      );
      expect(
        GenderMatching.wants(const <String>['female'], 'genderfluid'),
        isFalse,
      );
    });

    test('"otro" no dice qué es, así que no se excluye por él', () {
      for (final String bucket in GenderMatching.interestBuckets) {
        expect(GenderMatching.wants(<String>[bucket], 'other'), isTrue);
      }
    });

    test('un valor futuro desconocido tampoco excluye', () {
      expect(
        GenderMatching.wants(const <String>['female'], 'two_spirit'),
        isTrue,
      );
    });

    test('toda identidad del onboarding es visible para alguien', () {
      const List<String> identidades = <String>[
        'female',
        'male',
        'non_binary',
        'trans_woman',
        'trans_man',
        'genderfluid',
        'agender',
        'other',
      ];
      for (final String gender in identidades) {
        final bool visible = GenderMatching.interestBuckets.any(
          (String bucket) => GenderMatching.wants(<String>[bucket], gender),
        );
        expect(
          visible,
          isTrue,
          reason: '"$gender" no lo vería nadie que declare a quién busca',
        );
      }
    });
  });

  group('GenderMatching.bucketsFor', () {
    test('cada casilla devuelta es una casilla real de interestedIn', () {
      for (final String gender in <String>[
        'female',
        'male',
        'non_binary',
        'trans_woman',
        'trans_man',
        'genderfluid',
        'agender',
        'other',
        '',
      ]) {
        for (final String bucket in GenderMatching.bucketsFor(gender)) {
          expect(GenderMatching.interestBuckets, contains(bucket));
        }
      }
    });
  });
}
