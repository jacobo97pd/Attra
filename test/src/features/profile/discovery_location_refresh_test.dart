import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:attra/src/features/profile/data/discovery_publisher.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// El síntoma que se venía a arreglar, visto desde FUERA: "he subido una historia
/// desde Valencia y hasta que no he puesto el modo viajes como si estuviese en
/// Madrid, no he visto la historia en el descubrir personas".
///
/// Guardar la ubicación nueva en `users/{uid}` no basta: si no se republica
/// `discovery/{uid}`, los demás te siguen viendo donde estabas. Esta prueba
/// recorre la cadena de datos completa: `users.location` → payload público →
/// filtro del feed de otra persona.
const double kMadridLat = 40.4168;
const double kMadridLng = -3.7038;
const double kValenciaLat = 39.4699;
const double kValenciaLng = -0.3763;

Map<String, dynamic> _user({
  required double latitude,
  required double longitude,
  DateTime? locationUpdatedAt,
  bool traveling = false,
}) {
  return <String, dynamic>{
    'uid': 'mudado',
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
    'location': <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'permissionStatus': 'granted',
      'permissionGranted': true,
      if (locationUpdatedAt != null)
        'updatedAt': locationUpdatedAt.toIso8601String(),
    },
    'settings': <String, dynamic>{
      if (traveling)
        'travel': <String, dynamic>{
          'active': true,
          'iso2': 'ES',
          'city': 'Madrid',
          'country': 'España',
        },
    },
  };
}

/// Lo que vería otra persona en su feed.
SeedProfile _asSeenByOthers(Map<String, dynamic> published) =>
    SeedProfile.fromMap('mudado', published);

List<SeedProfile> _feedOfSomeoneIn({
  required SeedProfile candidate,
  required double lat,
  required double lng,
}) =>
    FeedFilter.apply(
      profiles: <SeedProfile>[candidate],
      myUid: 'local',
      myGender: 'female',
      myInterestedIn: const <String>['male'],
      excludedUids: const <String>{},
      myLat: lat,
      myLng: lng,
      myCountry: 'España',
      filters: const FeedFilters(maxDistanceKm: 50),
    );

void main() {
  group('republicar discovery tras refrescar la ubicación', () {
    test('con la ubicación vieja NO apareces para quien está en Valencia', () {
      final SeedProfile stale = _asSeenByOthers(DiscoveryPublisher.buildPayload(
        'mudado',
        _user(latitude: kMadridLat, longitude: kMadridLng),
      ));

      expect(
        _feedOfSomeoneIn(
            candidate: stale, lat: kValenciaLat, lng: kValenciaLng),
        isEmpty,
        reason: 'es el fallo reportado: publicado en Madrid, invisible en '
            'Valencia hasta activar el modo viaje a mano',
      );
    });

    test('con la ubicación refrescada SÍ apareces (y con la marca de frescura)',
        () {
      final DateTime refreshedAt = DateTime.utc(2026, 8, 5, 12, 0);
      final Map<String, dynamic> payload = DiscoveryPublisher.buildPayload(
        'mudado',
        _user(
          latitude: kValenciaLat,
          longitude: kValenciaLng,
          locationUpdatedAt: refreshedAt,
        ),
      );

      // Coordenadas publicadas redondeadas (~1,1 km), nunca exactas.
      final Map<String, dynamic> geo = payload['geo'] as Map<String, dynamic>;
      expect(geo['lat'], closeTo(kValenciaLat, 0.01));
      expect(geo['lng'], closeTo(kValenciaLng, 0.01));

      expect(
        _feedOfSomeoneIn(
          candidate: _asSeenByOthers(payload),
          lat: kValenciaLat,
          lng: kValenciaLng,
        ).map((SeedProfile p) => p.id),
        contains('mudado'),
      );
    });

    test('y dejas de aparecer para quien sigue en Madrid', () {
      final SeedProfile moved = _asSeenByOthers(DiscoveryPublisher.buildPayload(
        'mudado',
        _user(
          latitude: kValenciaLat,
          longitude: kValenciaLng,
          locationUpdatedAt: DateTime.utc(2026, 8, 5, 12, 0),
        ),
      ));

      expect(
        _feedOfSomeoneIn(candidate: moved, lat: kMadridLat, lng: kMadridLng),
        isEmpty,
      );
    });
  });

  group('el refresco no pisa el modo viaje', () {
    test('viajando, la ubicación refrescada NO se publica', () {
      // Regresión ya arreglada una vez: publicar las coordenadas reales junto al
      // país de destino dejaba al viajero invisible en TODOS los feeds. El
      // refresco guarda la ubicación real en users/{uid}, pero el payload público
      // sigue sin coordenadas mientras el viaje esté activo.
      final Map<String, dynamic> payload = DiscoveryPublisher.buildPayload(
        'mudado',
        _user(
          latitude: kValenciaLat,
          longitude: kValenciaLng,
          locationUpdatedAt: DateTime.utc(2026, 8, 5, 12, 0),
          traveling: true,
        ),
      );

      expect(payload.containsKey('geo'), isFalse);
      expect(payload['traveling'], isTrue);
    });
  });

  group('la marca de frescura del documento de usuario', () {
    test('es la que decide si hay que volver a mirar', () {
      // Contrato entre lo que se ESCRIBE (`location.updatedAt`) y lo que se LEE
      // para decidir. Si se dejara de escribir, la política volvería al
      // comportamiento roto: "hay coordenadas, no toco nada".
      final Map<String, dynamic> location =
          _user(latitude: kMadridLat, longitude: kMadridLng)['location']
              as Map<String, dynamic>;
      expect(location.containsKey('updatedAt'), isFalse);

      final DateTime now = DateTime.utc(2026, 8, 5, 12, 0);
      expect(
        LocationRefreshPolicy.decide(
          stored: const StoredLocation(
              latitude: kMadridLat, longitude: kMadridLng),
          now: now,
          permission: LocationAuthorization.granted,
          trigger: LocationRefreshTrigger.appStart,
        ).requestFix,
        isTrue,
        reason: 'sin marca de tiempo no se puede afirmar que la ubicación sea '
            'de hoy: es el estado en el que están los perfiles antiguos',
      );
    });
  });
}
