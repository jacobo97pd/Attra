import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

SeedProfile _p({
  required String id,
  String gender = '',
  List<String> interestedIn = const <String>[],
  int? age,
  String relationshipGoal = '',
  String smoking = '',
  int? heightCm,
  String photoUrl = '',
  String ethnicity = '',
  double? lat,
  double? lng,
}) {
  return SeedProfile(
    id: id,
    displayName: id,
    city: '',
    country: '',
    bio: '',
    gender: gender,
    interestedIn: interestedIn,
    relationshipGoal: relationshipGoal,
    smoking: smoking,
    heightCm: heightCm,
    ethnicity: ethnicity,
    lat: lat,
    lng: lng,
    orientation: const <String>[],
    age: age,
    jobTitle: '',
    company: '',
    interests: const <String>[],
    photoUrl: photoUrl,
    isBot: true,
    botProfileVersion: 1,
    botScenario: 'test',
    seedQualityScore: 0,
    photos: const <AdditionalPhoto>[],
  );
}

void main() {
  group('FeedFilter.apply', () {
    test('excluye mi propio uid', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[_p(id: 'me'), _p(id: 'other')],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
      );
      expect(result.map((p) => p.id), <String>['other']);
    });

    test('excluye likeados/pasados/matcheados/bloqueados', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'liked'),
          _p(id: 'passed'),
          _p(id: 'matched'),
          _p(id: 'fresh'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: <String>{'liked', 'passed', 'matched'},
      );
      expect(result.map((p) => p.id), <String>['fresh']);
    });

    test('hetero hombre no ve a una lesbiana (filtro bidireccional)', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'hetero_f', gender: 'female', interestedIn: <String>['male']),
          _p(
              id: 'lesbiana',
              gender: 'female',
              interestedIn: <String>['female']),
          _p(id: 'hetero_m', gender: 'male', interestedIn: <String>['female']),
        ],
        myUid: 'me',
        myGender: 'male',
        myInterestedIn: const <String>['female'],
        excludedUids: const <String>{},
      );
      // Solo la mujer hetero: me interesa (female) y yo le intereso (male).
      expect(result.map((p) => p.id), <String>['hetero_f']);
    });

    test('dato ausente en un lado es permisivo (no vacia el feed)', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          // Seed sin interestedIn: lado (b) permisivo => aparece.
          _p(id: 'seed_f', gender: 'female'),
        ],
        myUid: 'me',
        myGender: 'male',
        myInterestedIn: const <String>['female'],
        excludedUids: const <String>{},
      );
      expect(result.map((p) => p.id), <String>['seed_f']);
    });

    test('edad "no negociable" excluye fuera de rango; sin edad es permisivo',
        () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'joven', age: 20),
          _p(id: 'mayor', age: 50),
          _p(id: 'sinedad'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(
            minAge: 25, maxAge: 40, dealbreakers: <String>{FeedFilters.kAge}),
      );
      expect(result.map((p) => p.id), <String>['sinedad']);
    });

    test('filtro BLANDO (no deal-breaker) NO excluye', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'bajo', heightCm: 150),
          _p(id: 'alto', heightCm: 200),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        // altura puesta pero NO marcada "no negociable" => no excluye a nadie.
        // (La edad ya no sirve de ejemplo: es siempre dura y recíproca.)
        filters: const FeedFilters(minHeight: 170, maxHeight: 190),
      );
      expect(result.map((p) => p.id).toSet(), <String>{'bajo', 'alto'});
    });

    // C09: el rango de edad del onboarding no se usaba en ninguna parte. Ahora
    // es duro y RECÍPROCO, como en el directo (`isLiveCompatible`).
    group('edad recíproca', () {
      List<String> run({
        required List<SeedProfile> profiles,
        int minAge = FeedFilters.ageFloor,
        int maxAge = FeedFilters.ageCeil,
        int? myAge,
      }) =>
          FeedFilter.apply(
            profiles: profiles,
            myUid: 'me',
            myGender: '',
            myInterestedIn: const <String>[],
            excludedUids: const <String>{},
            filters: FeedFilters(minAge: minAge, maxAge: maxAge),
            myAge: myAge,
          ).map((SeedProfile p) => p.id).toList();

      test('mi rango excluye aunque no esté marcado "no negociable"', () {
        expect(
          run(
            profiles: <SeedProfile>[
              _p(id: 'joven', age: 20),
              _p(id: 'dentro', age: 30),
              _p(id: 'mayor', age: 50),
              _p(id: 'sinedad'),
            ],
            minAge: 25,
            maxAge: 40,
          ),
          <String>['dentro', 'sinedad'],
        );
      });

      test('Lucía (22, busca 22-30) no le sale a Pedro (58), ni al revés', () {
        final SeedProfile lucia =
            SeedProfile.fromMap('lucia', <String, dynamic>{
          'displayName': 'Lucía',
          'age': 22,
          'preferredAgeMin': 22,
          'preferredAgeMax': 30,
        });
        // Pedro, con rango abierto (18-80): Lucía cabe en el suyo, pero él no
        // cabe en el de ella.
        expect(run(profiles: <SeedProfile>[lucia], myAge: 58), isEmpty);
        // Alguien de 27 sí.
        expect(
            run(profiles: <SeedProfile>[lucia], myAge: 27), <String>['lucia']);
      });

      test('sin dato del otro lado es permisivo', () {
        final SeedProfile sinRango =
            SeedProfile.fromMap('x', <String, dynamic>{'age': 30});
        expect(
            run(profiles: <SeedProfile>[sinRango], myAge: 58), <String>['x']);
        // Sin mi edad tampoco se puede comprobar su rango.
        final SeedProfile conRango = SeedProfile.fromMap('y', <String, dynamic>{
          'age': 30,
          'preferredAgeMin': 25,
          'preferredAgeMax': 35,
        });
        expect(run(profiles: <SeedProfile>[conRango]), <String>['y']);
      });

      test('nunca por debajo de 18, pida lo que pida el rango', () {
        expect(
          run(
            profiles: <SeedProfile>[
              _p(id: 'menor', age: 16),
              _p(id: 'adulto', age: 18),
            ],
            minAge: 10,
          ),
          <String>['adulto'],
        );
      });

      test('80 es "80 o más": el rango por defecto no deja fuera a nadie', () {
        expect(
          run(profiles: <SeedProfile>[_p(id: 'senior', age: 85)]),
          <String>['senior'],
        );
      });
    });

    // D05: "Solo verificados" solo filtraba si además se marcaba "no
    // negociable" (apagado por defecto).
    test('"solo verificados" es duro, como "solo con foto"', () {
      final SeedProfile verificado = SeedProfile.fromMap(
          'v', <String, dynamic>{'displayName': 'V', 'verified': true});
      final SeedProfile sinVerificar =
          SeedProfile.fromMap('n', <String, dynamic>{'displayName': 'N'});
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[verificado, sinVerificar],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(verifiedOnly: true),
      );
      expect(result.map((SeedProfile p) => p.id), <String>['v']);
    });

    test('distancia "no negociable" excluye lejanos (haversine)', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'cerca', lat: 40.42, lng: -3.70), // Madrid
          _p(id: 'lejos', lat: 41.39, lng: 2.16), // Barcelona ~500km
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        myLat: 40.42,
        myLng: -3.70,
        filters: const FeedFilters(
            maxDistanceKm: 50, dealbreakers: <String>{FeedFilters.kDistance}),
      );
      expect(result.map((p) => p.id), <String>['cerca']);
    });

    test(
        'etnicidad/religión solo filtran si vienen (consentidas) y deal-breaker',
        () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'coincide', ethnicity: 'hispanic_latino'),
          _p(id: 'otra', ethnicity: 'east_asian'),
          _p(id: 'sin_consentir'), // ethnicity vacío => permisivo
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(
            ethnicity: 'hispanic_latino',
            dealbreakers: <String>{FeedFilters.kEthnicity}),
      );
      expect(result.map((p) => p.id).toSet(),
          <String>{'coincide', 'sin_consentir'});
    });

    test('filtro "mostrarme" por género', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'f', gender: 'female'),
          _p(id: 'm', gender: 'male'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(showGenders: <String>{'female'}),
      );
      expect(result.map((p) => p.id), <String>['f']);
    });

    test('filtro avanzado "qué busca" (relationshipGoal)', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'serio', relationshipGoal: 'serious_relationship'),
          _p(id: 'casual', relationshipGoal: 'casual'),
          _p(id: 'sindato'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(
            relationshipGoal: 'serious_relationship',
            dealbreakers: <String>{FeedFilters.kGoal}),
      );
      // serio coincide; casual fuera; sin dato permisivo => queda.
      expect(result.map((p) => p.id).toSet(), <String>{'serio', 'sindato'});
    });

    test('filtro "solo con foto"', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'confoto', photoUrl: 'https://x/p.jpg'),
          _p(id: 'sinfoto'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(onlyWithPhoto: true),
      );
      expect(result.map((p) => p.id), <String>['confoto']);
    });

    test('filtro avanzado tabaco (no fuma) + altura', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'nofuma_alto', smoking: 'never', heightCm: 180),
          _p(id: 'fuma', smoking: 'regularly', heightCm: 180),
          _p(id: 'nofuma_bajo', smoking: 'never', heightCm: 150),
          _p(id: 'sindato'),
        ],
        myUid: 'me',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        filters: const FeedFilters(
            smoking: 'never',
            minHeight: 170,
            maxHeight: 200,
            dealbreakers: <String>{FeedFilters.kSmoking, FeedFilters.kHeight}),
      );
      // nofuma_alto pasa; fuma fuera; nofuma_bajo fuera por altura;
      // sindato permisivo (sin smoking ni altura) => queda.
      expect(
          result.map((p) => p.id).toSet(), <String>{'nofuma_alto', 'sindato'});
    });

    test('sin preferencia propia ve a todos (salvo excluidos)', () {
      final result = FeedFilter.apply(
        profiles: <SeedProfile>[
          _p(id: 'a', gender: 'male', interestedIn: <String>['female']),
          _p(id: 'b', gender: 'female', interestedIn: <String>['female']),
        ],
        myUid: 'me',
        myGender: 'female',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
      );
      expect(result.map((p) => p.id).toSet(), <String>{'a', 'b'});
    });
  });
}
