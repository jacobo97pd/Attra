import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regla de país, radio y viajes de [FeedFilter].
///
/// El país se comparaba por NOMBRE con una tabla de ~15 alias: un teléfono en
/// catalán guardaba 'Espanya', uno en alemán 'Spanien', y esa gente dejaba de
/// verse con los demás españoles; el selector del viaje guarda 'Greece' y los
/// perfiles de allí dicen 'Grecia' o 'Ελλάδα'. Ahora manda el ISO2.
void main() {
  SeedProfile p(
    String id, {
    String country = '',
    String iso2 = '',
    String city = '',
    double? lat,
    double? lng,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) =>
      SeedProfile.fromMap(id, <String, dynamic>{
        'displayName': id,
        'currentCity': city,
        'currentCountryName': country,
        if (iso2.isNotEmpty) 'countryIso2': iso2,
        if (lat != null && lng != null)
          'geo': <String, dynamic>{'lat': lat, 'lng': lng},
        ...extra,
      });

  List<String> ids(List<SeedProfile> list) =>
      list.map((SeedProfile e) => e.id).toList(growable: false);

  List<SeedProfile> apply(
    List<SeedProfile> profiles, {
    String myCountry = '',
    String myCountryIso2 = '',
    double? myLat,
    double? myLng,
    int? maxKmOverride,
    String noGeoCity = '',
    bool requireGeo = false,
    bool travelersNeedGeo = false,
    String myCity = '',
  }) =>
      FeedFilter.apply(
        profiles: profiles,
        myUid: 'yo',
        myGender: '',
        myInterestedIn: const <String>[],
        excludedUids: const <String>{},
        myCountry: myCountry,
        myCountryIso2: myCountryIso2,
        myLat: myLat,
        myLng: myLng,
        maxKmOverride: maxKmOverride,
        noGeoCity: noGeoCity,
        requireGeo: requireGeo,
        travelersNeedGeo: travelersNeedGeo,
        myCity: myCity,
      );

  group('país por ISO2', () {
    test('un teléfono en catalán o alemán sigue siendo de España', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('cat', country: 'Espanya', iso2: 'ES'),
        p('de', country: 'Spanien', iso2: 'ES'),
        p('pt', country: 'Portugal', iso2: 'PT'),
      ], myCountry: 'España', myCountryIso2: 'ES');
      expect(ids(out), <String>['cat', 'de']);
    });

    test('viaje a Grecia: casa con "Grecia" y "Ελλάδα" por el código', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('es_nombre', country: 'Grecia', iso2: 'GR'),
        p('nativo', country: 'Ελλάδα', iso2: 'GR'),
        p('turquia', country: 'Turquía', iso2: 'TR'),
      ], myCountry: 'Greece', myCountryIso2: 'GR');
      expect(ids(out), <String>['es_nombre', 'nativo']);
    });

    test('sin código en un lado (seeds, fichas antiguas) cae al nombre', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('seed', country: 'España'),
        p('seed_catalan', country: 'Espanya'),
        p('seed_it', country: 'Italia'),
        p('sin_pais'),
      ], myCountry: 'Spain', myCountryIso2: 'ES');
      expect(ids(out), <String>['seed', 'seed_catalan', 'sin_pais'],
          reason: 'sin país en un lado no se excluye (permisivo)');
    });

    test('sameCountry: el código manda y el nombre es el respaldo', () {
      expect(FeedFilter.sameCountry('ES', 'España', 'ES', 'Spanien'), isTrue);
      expect(FeedFilter.sameCountry('ES', 'España', 'PT', 'España'), isFalse,
          reason: 'con código en los dos lados manda el código');
      expect(FeedFilter.sameCountry('ES', '', '', 'España'), isTrue);
      expect(FeedFilter.sameCountry('', 'Perú', '', 'Peru'), isTrue,
          reason: 'sin acentos');
      expect(FeedFilter.sameCountry('', '', '', 'España'), isNull);
    });
  });

  group('radio y ubicación', () {
    const double cadizLat = 36.53;
    const double cadizLng = -6.29;

    test('maxKmOverride manda sobre filtros y preferencia', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('jerez', lat: 36.69, lng: -6.14),
        p('sevilla', lat: 37.39, lng: -5.98),
      ], myLat: cadizLat, myLng: cadizLng, maxKmOverride: 30);
      expect(ids(out), <String>['jerez']);
    });

    test('viajando, sin coordenadas solo entra quien está en el destino', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('madrid_sin_geo', city: 'Madrid'),
        p('cadiz_sin_geo', city: 'Cádiz'),
        p('lucia', city: 'Cádiz', lat: cadizLat, lng: cadizLng),
      ],
          myLat: cadizLat,
          myLng: cadizLng,
          maxKmOverride: 100,
          // Grafía del dataset (sin acento), como la guarda el selector.
          noGeoCity: 'Cadiz');
      expect(ids(out), <String>['cadiz_sin_geo', 'lucia']);
    });

    test('requireGeo: donde se promete cercanía no entra quien no la tiene',
        () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('kabul_sin_geo', country: 'Afganistán'),
        p('cerca', lat: cadizLat, lng: cadizLng),
      ], myLat: cadizLat, myLng: cadizLng, requireGeo: true);
      expect(ids(out), <String>['cerca']);
    });

    test('una ficha "de viaje" cuyo viaje ya terminó no sale', () {
      final List<SeedProfile> out = apply(<SeedProfile>[
        p('caducado', extra: <String, dynamic>{
          'traveling': true,
          'travelUntil': DateTime.now().subtract(const Duration(days: 2)),
        }),
        p('vigente', extra: <String, dynamic>{
          'traveling': true,
          'travelUntil': DateTime.now().add(const Duration(days: 2)),
        }),
      ]);
      expect(ids(out), <String>['vigente']);
    });

    group('feed de casa: viajeros publicados sin centro', () {
      const double madridLat = 40.42;
      const double madridLng = -3.70;
      const Map<String, dynamic> deViaje = <String, dynamic>{
        'traveling': true,
      };
      // Pool del caso D02: una app antigua en Madrid activa un viaje a Cádiz
      // sin lat/lng y el backend la publica "de viaje" en España SIN `geo`.
      final List<SeedProfile> pool = <SeedProfile>[
        p('viajero_cadiz_sin_geo',
            city: 'Cádiz', country: 'España', iso2: 'ES', extra: deViaje),
        p('viajero_pais_entero', country: 'España', iso2: 'ES', extra: deViaje),
        p('viajero_madrid_sin_geo',
            city: 'Madrid', country: 'España', iso2: 'ES', extra: deViaje),
        p('viajero_cadiz_con_centro',
            city: 'Cádiz',
            country: 'España',
            iso2: 'ES',
            lat: 36.53,
            lng: -6.29,
            extra: deViaje),
        // Fichas normales sin coordenadas (mocks, gente sin ubicación): no
        // cambian, siguen con la regla de país.
        p('local_sin_geo', city: 'Sevilla', country: 'España', iso2: 'ES'),
        p('madrileno',
            city: 'Madrid',
            country: 'España',
            iso2: 'ES',
            lat: madridLat,
            lng: madridLng),
      ];

      test('desde Madrid no sale quien viaja a Cádiz sin centro', () {
        final List<SeedProfile> out = apply(
          pool,
          myCountry: 'España',
          myCountryIso2: 'ES',
          myLat: madridLat,
          myLng: madridLng,
          maxKmOverride: 100,
          travelersNeedGeo: true,
          myCity: 'Madrid',
        );
        expect(ids(out), <String>[
          'viajero_madrid_sin_geo',
          'local_sin_geo',
          'madrileno',
        ]);
      });

      test('en Cádiz sí (misma ciudad aunque cambie la grafía)', () {
        final List<SeedProfile> out = apply(
          pool,
          myCountry: 'España',
          myCountryIso2: 'ES',
          myLat: 36.53,
          myLng: -6.29,
          maxKmOverride: 100,
          travelersNeedGeo: true,
          myCity: 'Cadiz',
        );
        expect(
            ids(out),
            containsAll(<String>[
              'viajero_cadiz_sin_geo',
              'viajero_cadiz_con_centro',
            ]));
        expect(ids(out), isNot(contains('viajero_pais_entero')),
            reason: 'un viaje a todo el país no tiene ciudad con la que casar');
        expect(ids(out), isNot(contains('viajero_madrid_sin_geo')));
      });

      test('sin ciudad propia no se puede comprobar: no entra', () {
        final List<SeedProfile> out = apply(
          pool,
          myCountry: 'España',
          myCountryIso2: 'ES',
          travelersNeedGeo: true,
        );
        expect(ids(out), isNot(contains('viajero_cadiz_sin_geo')));
        expect(ids(out), contains('local_sin_geo'));
      });

      test('regla apagada (búsqueda IA, feed de viaje): como antes', () {
        final List<SeedProfile> out = apply(
          pool,
          myCountry: 'España',
          myCountryIso2: 'ES',
          myCity: 'Madrid',
        );
        expect(ids(out), contains('viajero_cadiz_sin_geo'));
      });
    });
  });

  test('canonCountry sin acentos y con los nombres de otros teléfonos', () {
    for (final String name in <String>[
      'España',
      'Espana',
      'Spain',
      'Espanya',
      'Spanien',
      'Espagne',
    ]) {
      expect(FeedFilter.canonCountry(name), 'es', reason: name);
    }
    expect(FeedFilter.canonCountry('México'), 'mx');
    expect(
        FeedFilter.canonCountry('Grecia'), FeedFilter.canonCountry('Greece'));
  });
}
