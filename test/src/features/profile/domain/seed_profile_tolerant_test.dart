import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una ficha mal formada no puede dejar el feed sin usuarios reales.
///
/// `discovery` y `seed_profiles` no validan tipos en las reglas (y
/// `users/{uid}`, de donde copia el backend, tampoco). Con casts duros
/// (`as String?`), un solo documento con `bio: 123` hacía lanzar la carga ENTERA
/// y el feed de todo el mundo se quedaba solo con los perfiles de prueba.
void main() {
  test('tipos equivocados cuentan como ausentes, sin lanzar', () {
    final SeedProfile p = SeedProfile.fromMap('raro', <String, dynamic>{
      'displayName': 5,
      'bio': 123,
      'gender': <String, dynamic>{'x': 1},
      'photos': 'x',
      'interestedIn': 'female',
      'heightCm': 'alto',
      'traveling': 'si',
      'verified': 1,
      'geo': <String, dynamic>{'lat': 'norte', 'lng': 999},
      'profilePrompts': <dynamic>[
        'suelto',
        <String, dynamic>{'id': 1, 'question': 'Q', 'answer': 'A'},
      ],
      'introAudio': <String, dynamic>{'url': 7, 'durationMs': 'largo'},
    });

    expect(p.displayName, 'Seed');
    expect(p.bio, '');
    expect(p.gender, '');
    expect(p.photos, isEmpty);
    expect(p.interestedIn, isEmpty);
    expect(p.heightCm, isNull);
    expect(p.traveling, isFalse);
    expect(p.verified, isFalse);
    expect(p.lat, isNull);
    expect(p.lng, isNull, reason: 'fuera de rango');
    expect(p.profilePrompts.single.question, 'Q');
  });

  test('parseDiscoveryDoc salta la ficha ilegible, no la carga entera', () {
    final List<SeedProfile> pool = <MapEntry<String, Map<String, dynamic>>>[
      const MapEntry<String, Map<String, dynamic>>(
          'buena', <String, dynamic>{'displayName': 'Ana'}),
      const MapEntry<String, Map<String, dynamic>>(
          'rara', <String, dynamic>{'displayName': 5, 'bio': 123}),
    ]
        .map((MapEntry<String, Map<String, dynamic>> e) =>
            UserRepository.parseDiscoveryDoc(e.key, e.value))
        .whereType<SeedProfile>()
        .toList();

    expect(pool.map((SeedProfile p) => p.id), <String>['buena', 'rara']);
  });

  test('pool por país: sin duplicados, sin mí y con una consulta caída', () {
    // Antes el pool era `discovery.limit(50)` sin orden: los 50 primeros por
    // uid, los mismos para todos. Ahora son varias consultas (país de casa,
    // país de destino y la antigua) que hay que juntar.
    MapEntry<String, Map<String, dynamic>> ficha(String id) =>
        MapEntry<String, Map<String, dynamic>>(
            id, <String, dynamic>{'displayName': id});
    final List<SeedProfile> pool = UserRepository.mergeDiscoveryPages(
      <List<MapEntry<String, Map<String, dynamic>>>?>[
        <MapEntry<String, Map<String, dynamic>>>[ficha('cadiz'), ficha('yo')],
        null, // la consulta del otro país falló (red, índice)
        <MapEntry<String, Map<String, dynamic>>>[ficha('cadiz'), ficha('zz')],
      ],
      excludeUid: 'yo',
    );
    expect(pool.map((SeedProfile p) => p.id), <String>['cadiz', 'zz']);

    expect(
      () => UserRepository.mergeDiscoveryPages(
          <List<MapEntry<String, Map<String, dynamic>>>?>[null, null],
          excludeUid: 'yo'),
      throwsStateError,
      reason: 'si fallan todas, quien llama se queda con los seeds',
    );
  });

  test('país comparable y fin del viaje publicados', () {
    final SeedProfile disc = SeedProfile.fromMap('d', <String, dynamic>{
      'currentCountryName': 'Espanya',
      'countryIso2': 'es',
    });
    final SeedProfile seed = SeedProfile.fromMap('s', <String, dynamic>{
      'profile': <String, dynamic>{
        'currentCountryName': 'España',
        'currentCountryCode': 'ES',
      },
    });
    expect(disc.countryIso2, 'ES');
    expect(seed.countryIso2, 'ES');

    final SeedProfile caducado = SeedProfile.fromMap('v', <String, dynamic>{
      'traveling': true,
      'travelUntil': DateTime.now().subtract(const Duration(hours: 1)),
    });
    expect(caducado.traveling, isFalse,
        reason: 'no se enseña "de viaje" a quien ya volvió');
    expect(caducado.travelExpired, isTrue);
  });
}
