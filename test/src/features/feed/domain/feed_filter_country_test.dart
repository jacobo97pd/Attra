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
