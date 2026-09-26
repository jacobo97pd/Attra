import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:attra/src/features/profile/data/discovery_publisher.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modo viaje: la ficha pública NO debe llevar las coordenadas reales.
///
/// El bug: se publicaba el país de DESTINO junto a las coordenadas de CASA. El
/// resultado era que el viajero no salía en ningún feed: fuera del suyo por el
/// filtro de país, y fuera del de destino por el filtro de radio contra unas
/// coordenadas que seguían a miles de kilómetros.
Map<String, dynamic> _user({
  required bool traveling,
  String destCountry = 'Japón',
  String destCity = 'Tokio',
}) {
  return <String, dynamic>{
    'uid': 'viajero',
    'onboardingCompleted': true,
    'profileCompleted': true,
    'isBot': false,
    'displayName': 'Alex',
    'photoUrl': 'https://example.test/a.jpg',
    'profile': <String, dynamic>{
      'visibleName': 'Alex',
      'gender': 'male',
      'currentCity': 'Madrid',
      'currentCountryName': 'España',
      'birthDate': '1995-05-20T00:00:00Z',
    },
    'preferences': <String, dynamic>{
      'interestedIn': <String>['female'],
    },
    // Coordenadas REALES: Madrid.
    'location': <String, dynamic>{'latitude': 40.4168, 'longitude': -3.7038},
    'settings': <String, dynamic>{
      if (traveling)
        'travel': <String, dynamic>{
          'active': true,
          'iso2': 'JP',
          'city': destCity,
          'country': destCountry,
        },
    },
  };
}

void main() {
  group('DiscoveryPublisher y modo viaje', () {
    test('sin viajar publica ciudad, país y coordenadas reales', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('viajero', _user(traveling: false));

      expect(out['traveling'], isFalse);
      expect(out['currentCity'], 'Madrid');
      expect(out['currentCountryName'], 'España');
      expect(out['geo'], isNotNull);
    });

    test('viaje SIN centro (antiguo o a un país): destino y NINGUNA coordenada',
        () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('viajero', _user(traveling: true));

      expect(out['traveling'], isTrue);
      expect(out['currentCity'], 'Tokio');
      expect(out['currentCountryName'], 'Japón');
      // Clave del arreglo: sin `geo`, el filtro de radio no puede descartarlo.
      // El doc se escribe con `set` SIN merge, así que omitirlo lo elimina.
      expect(out.containsKey('geo'), isFalse,
          reason: 'publicar las coordenadas de casa con el país de destino '
              'dejaba al viajero invisible en todos los feeds');
    });
  });

  group('El viajero es visible para quien está en el destino', () {
    /// Convierte la ficha publicada en el SeedProfile que vería otra persona.
    SeedProfile asSeenByOthers(Map<String, dynamic> published) =>
        SeedProfile.fromMap('viajero', published);

    test('viajando: aparece en el feed de alguien de Japón', () {
      final SeedProfile traveler = asSeenByOthers(
        DiscoveryPublisher.buildPayload('viajero', _user(traveling: true)),
      );

      final List<SeedProfile> visible = FeedFilter.apply(
        profiles: <SeedProfile>[traveler],
        myUid: 'local',
        myGender: 'female',
        myInterestedIn: const <String>['male'],
        excludedUids: const <String>{},
        // Quien mira está en Tokio, con coordenadas propias.
        myLat: 35.6762,
        myLng: 139.6503,
        myCountry: 'Japón',
        filters: const FeedFilters(maxDistanceKm: 50),
      );

      expect(visible.map((SeedProfile p) => p.id), contains('viajero'));
    });

    test('sin viajar: NO aparece para alguien de Japón', () {
      final SeedProfile home = asSeenByOthers(
        DiscoveryPublisher.buildPayload('viajero', _user(traveling: false)),
      );

      final List<SeedProfile> visible = FeedFilter.apply(
        profiles: <SeedProfile>[home],
        myUid: 'local',
        myGender: 'female',
        myInterestedIn: const <String>['male'],
        excludedUids: const <String>{},
        myLat: 35.6762,
        myLng: 139.6503,
        myCountry: 'Japón',
        filters: const FeedFilters(maxDistanceKm: 50),
      );

      expect(visible, isEmpty);
    });
  });

  group('Madrid → Cádiz con centro: solo le ven alrededor del destino', () {
    // Antes, sin `geo`, el viajero se saltaba el radio de TODOS: le veía toda
    // España, su propia ciudad incluida, con un "De viaje en Cádiz".
    Map<String, dynamic> aCadiz({String? until, Object? untilAt}) {
      final Map<String, dynamic> data = _user(traveling: false);
      (data['settings'] as Map<String, dynamic>)['travel'] = <String, dynamic>{
        'active': true,
        'iso2': 'ES',
        'city': 'Cadiz',
        'country': 'Spain',
        'lat': 36.5267,
        'lng': -6.2891,
        'geoSource': 'asset',
        'until': until ??
            DateTime.now().add(const Duration(days: 20)).toIso8601String(),
        if (untilAt != null) 'untilAt': untilAt,
      };
      return data;
    }

    List<String> quienLoVe(
      Map<String, dynamic> published, {
      required double lat,
      required double lng,
    }) =>
        FeedFilter.apply(
          profiles: <SeedProfile>[SeedProfile.fromMap('viajero', published)],
          myUid: 'local',
          myGender: 'female',
          myInterestedIn: const <String>['male'],
          excludedUids: const <String>{},
          myLat: lat,
          myLng: lng,
          myCountry: 'España',
          myCountryIso2: 'ES',
          filters: const FeedFilters(maxDistanceKm: 100),
        ).map((SeedProfile p) => p.id).toList(growable: false);

    test('publica el CENTRO del destino (nunca Madrid) y el país en ISO2', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('viajero', aCadiz());

      expect(out['traveling'], isTrue);
      expect(out['currentCity'], 'Cadiz');
      expect(out['countryIso2'], 'ES');
      expect(out['geo'], <String, dynamic>{'lat': 36.53, 'lng': -6.29});
      expect(out['travelUntil'], isNotNull);
    });

    test('alguien de Madrid con radio 100 km ya NO le ve; en Jerez sí', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('viajero', aCadiz());

      expect(quienLoVe(out, lat: 40.4168, lng: -3.7038), isEmpty);
      expect(quienLoVe(out, lat: 36.69, lng: -6.14), <String>['viajero']);
    });

    test('viaje caducado o sin plan: vuelve a casa, como el backend', () {
      final Map<String, dynamic> caducado = DiscoveryPublisher.buildPayload(
        'viajero',
        aCadiz(
            until: DateTime.now()
                .subtract(const Duration(days: 1))
                .toIso8601String()),
      );
      final Map<String, dynamic> sinPlan =
          DiscoveryPublisher.buildPayload('viajero', aCadiz(), isPaid: false);

      for (final Map<String, dynamic> out in <Map<String, dynamic>>[
        caducado,
        sinPlan,
      ]) {
        expect(out['traveling'], isFalse);
        expect(out['currentCity'], 'Madrid');
        expect(out['geo'], <String, dynamic>{'lat': 40.42, 'lng': -3.7});
        expect(out.containsKey('travelUntil'), isFalse);
      }
    });

    test('un centro sobrante de otro destino no se publica, como el backend',
        () {
      // "España" sin ciudad (la demo de App Review) sobre un documento que
      // aún tenía el centro de Cádiz: se publicaba en Cádiz.
      final Map<String, dynamic> pais = aCadiz();
      ((pais['settings'] as Map<String, dynamic>)['travel']
          as Map<String, dynamic>)['city'] = '';
      // Una versión antigua cambió a Barcelona sin tocar lat/lng.
      final Map<String, dynamic> otraCiudad = aCadiz();
      ((otraCiudad['settings'] as Map<String, dynamic>)['travel']
          as Map<String, dynamic>)
        ..['city'] = 'Barcelona'
        ..['geoCity'] = 'Cadiz'
        ..['geoIso2'] = 'ES';

      for (final Map<String, dynamic> data in <Map<String, dynamic>>[
        pais,
        otraCiudad,
      ]) {
        final Map<String, dynamic> out =
            DiscoveryPublisher.buildPayload('viajero', data);
        expect(out['traveling'], isTrue);
        expect(out.containsKey('geo'), isFalse);
      }
    });

    test('manda la fecha más tardía; una imposible cuenta como caducada', () {
      // Versión antigua que reactivó el viaje: `until` nuevo, `untilAt` viejo.
      final Map<String, dynamic> reactivado = DiscoveryPublisher.buildPayload(
        'viajero',
        aCadiz(
          untilAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      );
      expect(reactivado['traveling'], isTrue);

      final Map<String, dynamic> lejano = DiscoveryPublisher.buildPayload(
        'viajero',
        aCadiz(
            until: DateTime.now()
                .add(const Duration(days: 400))
                .toIso8601String()),
      );
      expect(lejano['traveling'], isFalse);
      expect(lejano['currentCity'], 'Madrid');
    });

    test('sin viajar publica el ISO2 de casa aunque el nombre sea otro idioma',
        () {
      final Map<String, dynamic> data = _user(traveling: false);
      (data['profile'] as Map<String, dynamic>)
        ..['currentCountryName'] = 'Espanya'
        ..['currentCountryIso2'] = 'ES';
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('viajero', data);

      expect(out['countryIso2'], 'ES');
      // Paridad con el backend: el modo Amigos también se publica.
      expect(out['intentMode'], 'dating');
      expect(out['socialInterests'], isEmpty);
    });
  });
}
