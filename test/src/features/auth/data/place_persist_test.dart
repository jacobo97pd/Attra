import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/data/location_refresh_service.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// La ciudad y el país tienen que viajar en la MISMA escritura que las
/// coordenadas.
///
/// Los escribía SOLO el selector manual del onboarding. Al hacer que las
/// coordenadas se refresquen solas quedaron desfasados respecto a ellas, y eso
/// es PEOR que tenerlo todo rancio a la vez: cruzas una frontera, tus
/// coordenadas dicen Lisboa y tu país sigue diciendo España, así que la regla
/// de país te enseña españoles y la de radio los descarta a todos. Y dejas de
/// ser visible para los de tu zona nueva, porque el país que publicas es de
/// otro sitio.
class _FakeResolver implements PlaceResolver {
  _FakeResolver(this._place);

  final ResolvedPlace? _place;
  int llamadas = 0;

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    llamadas++;
    return _place;
  }
}

class _ExplosiveResolver implements PlaceResolver {
  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    throw StateError('geocodificador caído');
  }
}

class _FakeSource implements DeviceLocationSource {
  _FakeSource({required this.cached});

  final LocationFix? cached;

  @override
  Future<LocationAuthorization> authorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationAuthorization> requestAuthorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationFix?> lastKnownFix() async => cached;

  @override
  Future<LocationFix?> currentFix({Duration timeout = Duration.zero}) async =>
      cached;
}

void main() {
  const ResolvedPlace valencia = ResolvedPlace(
    city: 'Valencia',
    countryName: 'España',
    countryIso2: 'ES',
  );

  final DateTime clock = DateTime.utc(2026, 8, 8, 12);

  ResolvedPlace? capturado;
  bool guardado = false;

  Future<void> persist({
    required double latitude,
    required double longitude,
    required DateTime fixedAt,
    String? permissionStatus,
    bool? permissionGranted,
    ResolvedPlace? place,
  }) async {
    capturado = place;
    guardado = true;
  }

  setUp(() {
    capturado = null;
    guardado = false;
  });

  /// Está en Valencia; lo guardado dice Madrid. ~300 km: mudanza de verdad.
  _FakeSource enValencia() => _FakeSource(
        cached: LocationFix(
          latitude: 39.47,
          longitude: -0.38,
          timestamp: clock.subtract(const Duration(minutes: 2)),
          fromCache: true,
        ),
      );

  StoredLocation madrid() => StoredLocation(
        latitude: 40.42,
        longitude: -3.70,
        updatedAt: clock.subtract(const Duration(days: 30)),
        measuredAt: clock.subtract(const Duration(days: 30)),
      );

  test('al mudarse se resuelve el sitio y viaja con las coordenadas', () async {
    final _FakeResolver resolver = _FakeResolver(valencia);
    await LocationRefreshService(
      source: enValencia(),
      persist: persist,
      placeResolver: resolver,
    ).refresh(
      stored: madrid(),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(guardado, isTrue);
    expect(capturado?.city, 'Valencia');
    expect(capturado?.countryName, 'España');
    expect(resolver.llamadas, 1,
        reason: 'una sola vez: el geocodificador de iOS va por tasa');
  });

  test('si el geocodificador revienta, la ubicación se guarda igual', () async {
    // No poder nombrar la ciudad NO puede impedir guardar unas coordenadas
    // buenas: se perdería el arreglo entero por un fallo de red.
    await LocationRefreshService(
      source: enValencia(),
      persist: persist,
      placeResolver: _ExplosiveResolver(),
    ).refresh(
      stored: madrid(),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(guardado, isTrue, reason: 'las coordenadas sí se guardan');
    expect(capturado, isNull, reason: 'el sitio anterior se conserva entero');
  });

  test('sin resolutor todo lo demás sigue funcionando', () async {
    await LocationRefreshService(
      source: enValencia(),
      persist: persist,
    ).refresh(
      stored: madrid(),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(guardado, isTrue);
    expect(capturado, isNull);
  });

  test('viajando NO se gasta una llamada al geocodificador', () async {
    // Con viaje activo el feed está anclado al destino y las coordenadas
    // reales ni se publican: resolver la ciudad sería gastar cuota para nada.
    final _FakeResolver resolver = _FakeResolver(valencia);
    await LocationRefreshService(
      source: enValencia(),
      persist: persist,
      placeResolver: resolver,
    ).refresh(
      stored: madrid(),
      trigger: LocationRefreshTrigger.appResume,
      travelActive: true,
    );

    expect(resolver.llamadas, 0);
  });
}
