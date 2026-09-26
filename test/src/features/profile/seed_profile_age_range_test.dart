import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// El rango de edad que busca cada perfil (C09): discovery lo publica plano y
/// los seeds lo traen en `preferences`. Sin él el feed no podía ser recíproco.
void main() {
  test('discovery: plano', () {
    final SeedProfile p = SeedProfile.fromMap('a', <String, dynamic>{
      'preferredAgeMin': 22,
      'preferredAgeMax': 30,
    });
    expect(p.preferredAgeMin, 22);
    expect(p.preferredAgeMax, 30);
  });

  test('seed_profiles: dentro de preferences', () {
    final SeedProfile p = SeedProfile.fromMap('s', <String, dynamic>{
      'preferences': <String, dynamic>{
        'preferredAgeMin': 30,
        'preferredAgeMax': 45,
      },
    });
    expect(p.preferredAgeMin, 30);
    expect(p.preferredAgeMax, 45);
  });

  test('sin dato o con basura: null (permisivo), nunca un rango roto', () {
    final SeedProfile vacio = SeedProfile.fromMap('v', <String, dynamic>{});
    expect(vacio.preferredAgeMin, isNull);
    expect(vacio.preferredAgeMax, isNull);

    final SeedProfile basura = SeedProfile.fromMap('b', <String, dynamic>{
      'preferredAgeMin': 'veinte',
      'preferredAgeMax': 3,
    });
    expect(basura.preferredAgeMin, isNull);
    expect(basura.preferredAgeMax, isNull);
  });
}
