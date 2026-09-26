import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/social/domain/intent_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// Respaldo de MUESTRA de [FeedFilter.sampleProfiles].
///
/// Una cuenta nueva fuera de España (el revisor de App Review en EE. UU.) veía
/// Descubrir vacío: todos los semilla son de España y la regla de país los
/// tiraba. El respaldo levanta SOLO país y radio, y SOLO para semillas.
void main() {
  // Madrid: los semilla están aquí; "yo" estoy en Nueva York.
  const double madridLat = 40.4168;
  const double madridLng = -3.7038;

  SeedProfile perfil(
    String id, {
    bool bot = true,
    String gender = 'female',
    List<String> interestedIn = const <String>['male'],
    String intent = 'dating',
    int age = 30,
    int? prefMin,
    int? prefMax,
  }) =>
      SeedProfile.fromMap(id, <String, dynamic>{
        'displayName': id,
        'isBot': bot,
        'currentCity': 'Madrid',
        'currentCountryName': 'España',
        'countryIso2': 'ES',
        'geo': <String, dynamic>{'lat': madridLat, 'lng': madridLng},
        'gender': gender,
        'interestedIn': interestedIn,
        'intentMode': intent,
        'age': age,
        if (prefMin != null) 'preferredAgeMin': prefMin,
        if (prefMax != null) 'preferredAgeMax': prefMax,
      });

  List<String> muestra(
    List<SeedProfile> profiles, {
    Set<String> excluded = const <String>{},
    FeedFilters filters = const FeedFilters(minAge: 18, maxAge: 99),
    IntentMode intent = IntentMode.dating,
    int? myAge = 31,
  }) =>
      FeedFilter.sampleProfiles(
        profiles: profiles,
        myUid: 'yo',
        myGender: 'male',
        myInterestedIn: const <String>['female'],
        excludedUids: excluded,
        filters: filters,
        myIntent: intent,
        myAge: myAge,
      ).map((SeedProfile p) => p.id).toList(growable: false);

  test('la regla de país vacía el feed de quien vive en EE. UU.', () {
    // El punto de partida: con país y radio, nadie.
    final List<SeedProfile> out = FeedFilter.apply(
      profiles: <SeedProfile>[perfil('ana')],
      myUid: 'yo',
      myGender: 'male',
      myInterestedIn: const <String>['female'],
      excludedUids: const <String>{},
      myCountry: 'Estados Unidos',
      myCountryIso2: 'US',
      myLat: 40.7128,
      myLng: -74.0060,
    );
    expect(out, isEmpty);
  });

  test('las semillas de otro país rellenan el feed vacío', () {
    expect(muestra(<SeedProfile>[perfil('ana'), perfil('ines')]),
        <String>['ana', 'ines']);
  });

  test('NUNCA entra una persona real de otro país', () {
    expect(
      muestra(<SeedProfile>[perfil('real', bot: false), perfil('ana')]),
      <String>['ana'],
    );
  });

  test('se siguen aplicando exclusiones, género, intención y edad', () {
    final List<SeedProfile> pool = <SeedProfile>[
      perfil('ok'),
      perfil('ya_vista'),
      // No le intereso: la reciprocidad de género sigue siendo dura.
      perfil('no_me_busca', interestedIn: const <String>['female']),
      // Solo amistad y yo busco citas.
      perfil('amistad', intent: 'friends'),
      // Fuera de MI rango de edad.
      perfil('mayor', age: 70),
      // Yo (31) fuera de SU rango.
      perfil('rango_suyo', prefMin: 40, prefMax: 50),
    ];
    expect(
      muestra(
        pool,
        excluded: const <String>{'ya_vista'},
        filters: const FeedFilters(minAge: 18, maxAge: 60),
      ),
      <String>['ok'],
    );
  });

  test('los filtros duros del usuario también cuentan', () {
    expect(
      muestra(
        <SeedProfile>[perfil('ana')],
        filters: const FeedFilters(minAge: 18, maxAge: 99, verifiedOnly: true),
      ),
      isEmpty,
      reason: '"solo verificados" no se levanta por ser una muestra',
    );
  });

  test('discovery solo trae personas reales aunque falte isBot', () {
    // El parser antiguo daba isBot=true a una ficha sin el campo: una persona
    // real de otro país se habría colado como "semilla".
    final List<SeedProfile> pool = UserRepository.mergeDiscoveryPages(
      <List<MapEntry<String, Map<String, dynamic>>>?>[
        <MapEntry<String, Map<String, dynamic>>>[
          const MapEntry<String, Map<String, dynamic>>(
              'sin_campo', <String, dynamic>{'displayName': 'Ana'}),
          const MapEntry<String, Map<String, dynamic>>(
              'mal_marcada', <String, dynamic>{'isBot': true}),
        ],
      ],
      excludeUid: 'yo',
    );
    expect(pool.every((SeedProfile p) => !p.isBot), isTrue);
    expect(SeedProfile.fromMap('x', const <String, dynamic>{}).isBot, isFalse,
        reason: 'isBot solo cuenta si el documento lo dice');
  });
}
