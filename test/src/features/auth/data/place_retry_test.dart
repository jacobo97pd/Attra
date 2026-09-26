import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/data/location_refresh_service.dart';
import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un geocodificador que falló UNA vez dejaba el país atrasado todo el viaje.
///
/// Un español llega a Lisboa sin datos (o con CLGeocoder limitado por tasa): las
/// coordenadas se guardan (Lisboa) pero el país se queda en España. En la
/// siguiente lectura las coordenadas ya no se "mueven", así que nadie volvía a
/// preguntar: portugueses y españoles lo descartaban a la vez (país y radio) y
/// no lo veía nadie. Ahora se apunta dónde se resolvió el sitio y, si queda
/// atrás, se vuelve a preguntar.
void main() {
  final DateTime clock = DateTime.utc(2026, 9, 1, 12);
  const double lisboaLat = 38.72;
  const double lisboaLng = -9.14;
  const ResolvedPlace lisboa = ResolvedPlace(
    city: 'Lisboa',
    countryName: 'Portugal',
    countryIso2: 'PT',
  );

  /// Ya en Lisboa (coordenadas guardadas y recientes) pero con el sitio
  /// resuelto por última vez en Madrid.
  StoredLocation atrasado() => StoredLocation(
        latitude: lisboaLat,
        longitude: lisboaLng,
        updatedAt: clock.subtract(const Duration(minutes: 20)),
        measuredAt: clock.subtract(const Duration(minutes: 20)),
        placeLatitude: 40.42,
        placeLongitude: -3.70,
      );

  group('LocationRefreshPolicy', () {
    test('needsPlaceRetry: sitio atrás, al día o sin marca', () {
      expect(LocationRefreshPolicy.needsPlaceRetry(atrasado()), isTrue);
      expect(
          LocationRefreshPolicy.needsPlaceRetry(const StoredLocation(
            latitude: lisboaLat,
            longitude: lisboaLng,
            placeLatitude: lisboaLat,
            placeLongitude: lisboaLng,
          )),
          isFalse);
      expect(
          LocationRefreshPolicy.needsPlaceRetry(
              const StoredLocation(latitude: lisboaLat, longitude: lisboaLng)),
          isTrue,
          reason: 'documentos anteriores a la marca: una vez, para fecharlos');
      expect(LocationRefreshPolicy.needsPlaceRetry(const StoredLocation()),
          isFalse);
    });

    test('un solo umbral para guardar y para recargar', () {
      expect(LocationRefreshPolicy.moveThresholdForRadius(10), 5);
      expect(LocationRefreshPolicy.moveThresholdForRadius(1), 1);
      expect(LocationRefreshPolicy.moveThresholdForRadius(100), 10);
    });
  });

  group('LocationRefreshService', () {
    late List<ResolvedPlace?> guardados;

    Future<void> persist({
      required double latitude,
      required double longitude,
      required DateTime fixedAt,
      String? permissionStatus,
      bool? permissionGranted,
      ResolvedPlace? place,
    }) async {
      guardados.add(place);
    }

    setUp(() => guardados = <ResolvedPlace?>[]);

    LocationRefreshService servicio(_Resolver resolver) =>
        LocationRefreshService(
          source: _EnLisboa(clock),
          persist: persist,
          placeResolver: resolver,
          clock: () => clock,
        );

    test('sin moverse, vuelve a preguntar el sitio y lo guarda', () async {
      final _Resolver resolver = _Resolver(lisboa);
      final LocationRefreshOutcome out = await servicio(resolver).refresh(
        stored: atrasado(),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(resolver.calls, 1);
      expect(guardados, hasLength(1));
      expect(guardados.single?.countryIso2, 'PT');
      expect(out.persisted, isTrue);
    });

    test('si vuelve a fallar no escribe nada y no insiste en la sesión',
        () async {
      final _Resolver resolver = _Resolver(null);
      final LocationRefreshService s = servicio(resolver);
      await s.refresh(
          stored: atrasado(), trigger: LocationRefreshTrigger.appResume);
      await s.refresh(
          stored: atrasado(), trigger: LocationRefreshTrigger.appResume);

      expect(resolver.calls, 1, reason: 'CLGeocoder va por tasa');
      expect(guardados, isEmpty,
          reason: 'coordenadas iguales y sin sitio: nada que escribir');
    });

    test('con el sitio al día no se gasta geocodificador', () async {
      final _Resolver resolver = _Resolver(lisboa);
      await servicio(resolver).refresh(
        stored: StoredLocation(
          latitude: lisboaLat,
          longitude: lisboaLng,
          updatedAt: clock.subtract(const Duration(minutes: 20)),
          placeLatitude: lisboaLat,
          placeLongitude: lisboaLng,
        ),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(resolver.calls, 0);
      expect(guardados, isEmpty);
    });

    test('viajando no se reintenta', () async {
      final _Resolver resolver = _Resolver(lisboa);
      await servicio(resolver).refresh(
        stored: atrasado(),
        trigger: LocationRefreshTrigger.appResume,
        travelActive: true,
      );

      expect(resolver.calls, 0);
    });
  });

  group('UserRepository.buildDeviceLocationPatch', () {
    test('el ISO2 va a las DOS claves y se apunta dónde se resolvió', () {
      final ({Map<String, dynamic> profile, Map<String, dynamic> location}) p =
          UserRepository.buildDeviceLocationPatch(
        latitude: lisboaLat,
        longitude: lisboaLng,
        fixedAt: clock,
        place: lisboa,
      );

      expect(p.profile['currentCountryName'], 'Portugal');
      expect(p.profile['currentCountryIso2'], 'PT');
      expect(p.profile['currentCountryCode'], 'PT',
          reason: 'si no, tras cruzar la frontera quedaba un nombre nuevo con '
              'el código viejo del onboarding');
      expect(p.location['placeLat'], lisboaLat);
      expect(p.location['placeLng'], lisboaLng);
    });

    test('sin sitio no se toca ni el país ni la marca del sitio', () {
      final ({Map<String, dynamic> profile, Map<String, dynamic> location}) p =
          UserRepository.buildDeviceLocationPatch(
        latitude: lisboaLat,
        longitude: lisboaLng,
        fixedAt: clock,
      );

      expect(p.profile, isEmpty);
      expect(p.location.containsKey('placeLat'), isFalse);
      expect(p.location['latitude'], lisboaLat);
    });
  });
}

class _Resolver implements PlaceResolver {
  _Resolver(this._place);

  final ResolvedPlace? _place;
  int calls = 0;

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    calls++;
    return _place;
  }
}

/// El sistema sabe que está en Lisboa desde hace un minuto.
class _EnLisboa implements DeviceLocationSource {
  _EnLisboa(this._now);

  final DateTime _now;

  LocationFix get _fix => LocationFix(
        latitude: 38.72,
        longitude: -9.14,
        timestamp: _now.subtract(const Duration(minutes: 1)),
        fromCache: true,
      );

  @override
  Future<LocationAuthorization> authorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationAuthorization> requestAuthorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationFix?> lastKnownFix() async => _fix;

  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      _fix;
}
