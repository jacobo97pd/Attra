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

    test('viajando publica el destino y NO publica coordenadas', () {
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
}
