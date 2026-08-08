import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';

/// Enganche del refresco de ubicación en el feed: al arrancar, al volver del
/// fondo y con el aviso que explica lo que no se puede arreglar solo.
void main() {
  const double madridLat = 40.4168;
  const double madridLng = -3.7038;
  const double valenciaLat = 39.4699;
  const double valenciaLng = -0.3763;

  testWidgets('al arrancar refresca la ubicación rancia y la guarda',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(
          latitude: valenciaLat, longitude: valenciaLng),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        // Ubicación de hace tres días: el fallo era justo este caso, que se
        // consideraba "ya tengo coordenadas, no toco nada".
        locationUpdatedAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    expect(source.currentFixCalls, 1);
    expect(saved.calls, 1);
    expect(saved.lastLatitude, valenciaLat);
    expect(saved.lastPermissionGranted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con ubicación reciente no gasta GPS al arrancar',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    expect(source.currentFixCalls, 0);
    expect(saved.calls, 0);
  });

  testWidgets('al volver del fondo vuelve a mirar dónde está',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // Al arrancar todavía está en casa; mientras la app estaba en el fondo se ha
    // ido a otra ciudad y la caché del sistema ya lo sabe (por eso la llegada se
    // detecta sin encender el GPS).
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: madridLat,
        longitude: madridLng,
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        fromCache: true,
      ),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();
    expect(saved.calls, 0, reason: 'nada que hacer al arrancar');

    // La app vuelve del fondo (alguien que viaja abre la app al llegar).
    source.cached = LocationFix(
      latitude: valenciaLat,
      longitude: valenciaLng,
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      fromCache: true,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(saved.calls, 1);
    expect(saved.lastLongitude, valenciaLng);
    expect(source.currentFixCalls, 0);
  });

  testWidgets('un fix que confirma el mismo sitio no recarga el feed',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // `_load()` hace varias lecturas de red: recargar para acabar filtrando por
    // las mismas coordenadas sería trabajo (y datos) para nada.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: madridLat, longitude: madridLng),
    );
    final _Loads loads = _Loads();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      source: source,
      saved: _Saved(),
      loads: loads,
    ));
    await tester.pumpAndSettle();

    expect(source.currentFixCalls, 1, reason: 'la ubicación estaba rancia');
    expect(loads.calls, 1);
  });

  testWidgets('un fix en otra ciudad sí recarga el feed',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final _Loads loads = _Loads();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      source: source,
      saved: _Saved(),
      loads: loads,
    ));
    await tester.pumpAndSettle();

    expect(loads.calls, 2,
        reason: 'el feed estaba filtrado alrededor de la ciudad de antes');
  });

  testWidgets('cruzar la frontera no deja el feed vacío: se ignora el país',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // Coordenadas de VERDAD en Lisboa y país declarado "España" (solo se escribe
    // en el onboarding, con un selector manual, y en la app no hay
    // geocodificación inversa). La regla de país tiraba a los portugueses de al
    // lado y la de radio a los españoles: feed VACÍO, sin explicación y sin
    // salida (el modo viaje es de pago).
    const double lisboaLat = 38.7223;
    const double lisboaLng = -9.1393;
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
    );

    await tester.pumpWidget(_host(
      user: _user(
        latitude: lisboaLat,
        longitude: lisboaLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      source: source,
      saved: _Saved(),
      profiles: <SeedProfile>[
        SeedProfile.fromMap('vecina', <String, dynamic>{
          'displayName': 'Ana',
          'currentCity': 'Lisboa',
          'currentCountryName': 'Portugal',
          'gender': 'female',
          'geo': <String, dynamic>{'lat': lisboaLat, 'lng': lisboaLng},
          'photos': <String>['https://example.test/a.jpg'],
        }),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No hay nadie de España en tu zona'),
        findsOneWidget);
    expect(find.textContaining('No hay más personas'), findsNothing);
  });

  testWidgets('la ubicación llega antes que la carga y NO la duplica',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // Carrera real de producción: `_load()` se suspende en la primera lectura de
    // red y la ronda de ubicación (dos llamadas de canal nativo) termina antes.
    // Si el feed deduce "me cargué sin ubicación" de que aún no ha apuntado sus
    // coordenadas, cada apertura de la app costaba DOS cargas completas.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: madridLat,
        longitude: madridLng,
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
        fromCache: true,
      ),
    );
    final _Loads loads = _Loads();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
      source: source,
      saved: _Saved(),
      loads: loads,
      // La carga tarda: la ronda de ubicación gana la carrera, como en el móvil.
      loadDelay: const Duration(milliseconds: 40),
    ));
    await tester.pumpAndSettle();

    expect(loads.calls, 1);
  });

  testWidgets('una lectura que no se ha guardado no se adopta como "yo"',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // La política rechaza guardar una caché ANTERIOR a lo ya guardado ("sería
    // retroceder"). Adoptarla igualmente filtraba el feed desde un punto que
    // `discovery/{uid}` no publica: dabas likes a gente que no te podía ver.
    final DateTime storedAt = DateTime.now().subtract(const Duration(minutes: 5));
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: storedAt.subtract(const Duration(minutes: 15)),
        fromCache: true,
      ),
    );
    final _Saved saved = _Saved();
    final _Loads loads = _Loads();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: storedAt,
      ),
      source: source,
      saved: saved,
      loads: loads,
    ));
    await tester.pumpAndSettle();

    expect(saved.calls, 0, reason: 'la política la rechazó');
    expect(loads.calls, 1,
        reason: 'y sin adoptarla no hay nada que recargar: el feed sigue '
            'filtrando desde donde los demás te ven');
  });

  testWidgets('permiso denegado: lo dice y el gesto del usuario lo arregla',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.denied,
      grantedOnRequest: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    // No se abre el diálogo del sistema por abrir el feed (iOS lo penaliza).
    expect(source.requestCalls, 0);
    final Finder banner = find.textContaining('Sin permiso de ubicación');
    expect(banner, findsOneWidget);

    await tester.tap(banner);
    await tester.pumpAndSettle();

    expect(source.requestCalls, 1);
    expect(saved.calls, 1);
    expect(saved.lastLatitude, valenciaLat);
    // Concedido y guardado: el aviso desaparece.
    expect(find.textContaining('Sin permiso de ubicación'), findsNothing);
  });

  testWidgets('localización apagada: se avisa sin tocar el GPS',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.serviceDisabled);

    await tester.pumpWidget(_host(
      user: _user(),
      source: source,
      saved: _Saved(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('está apagada'), findsOneWidget);
    expect(source.currentFixCalls, 0);
  });

  testWidgets('al apagar el modo viaje se vuelve a mirar dónde estás',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // Mientras viajabas no se publicaban tus coordenadas; al apagarlo vuelven a
    // publicarse, así que hay que refrescarlas antes de que los demás te vean en
    // la ciudad de la que te fuiste (aunque la marca sea reciente).
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        traveling: true,
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();
    expect(source.currentFixCalls, 0);

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    expect(source.currentFixCalls, 1);
    expect(saved.lastLatitude, valenciaLat);
  });

  testWidgets('viajando no hay aviso ni GPS, pero sí se guarda la real',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        fromCache: true,
      ),
      current: const LocationFix(latitude: 0, longitude: 0),
    );
    final _Saved saved = _Saved();

    await tester.pumpWidget(_host(
      user: _user(
        latitude: madridLat,
        longitude: madridLng,
        locationUpdatedAt: DateTime.now().subtract(const Duration(days: 5)),
        traveling: true,
      ),
      source: source,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    expect(source.currentFixCalls, 0,
        reason: 'el feed está anclado al destino: el fix no cambiaría nada');
    expect(saved.calls, 1,
        reason: 'la ubicación real se sigue guardando en users/{uid} aunque el '
            'modo viaje impida publicarla');
    expect(find.textContaining('Tu ubicación puede estar'), findsNothing);
  });
}

AppUser _user({
  double? latitude,
  double? longitude,
  DateTime? locationUpdatedAt,
  bool traveling = false,
}) {
  return AppUser(
    uid: 'yo',
    email: 'yo@example.test',
    displayName: 'Yo',
    photoUrl: '',
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    latitude: latitude,
    longitude: longitude,
    locationUpdatedAt: locationUpdatedAt,
    countryName: 'España',
    travelActive: traveling,
    travelCountry: traveling ? 'España' : '',
    travelCity: traveling ? 'Madrid' : '',
  );
}

Widget _host({
  required AppUser user,
  required _FakeSource source,
  required _Saved saved,
  _Loads? loads,
  Duration? loadDelay,
  List<SeedProfile> profiles = const <SeedProfile>[],
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: FeedScreen(
        user: user,
        onLoadSeedProfiles: () async {
          loads?.calls++;
          if (loadDelay != null) await Future<void>.delayed(loadDelay);
          return profiles;
        },
        matchService: _MatchServiceStub(),
        chatService: _ChatServiceStub(),
        locationSource: source,
        onDeviceLocation: saved.call,
      ),
    ),
  );
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Cuenta las cargas del feed (cada una son varias lecturas de red).
class _Loads {
  int calls = 0;
}

class _Saved {
  int calls = 0;
  double? lastLatitude;
  double? lastLongitude;
  DateTime? lastFixedAt;
  bool? lastPermissionGranted;

  Future<void> call({
    required double latitude,
    required double longitude,
    required DateTime fixedAt,
    String? permissionStatus,
    bool? permissionGranted,
    ResolvedPlace? place,
  }) async {
    calls++;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastFixedAt = fixedAt;
    lastPermissionGranted = permissionGranted;
  }
}

class _FakeSource implements DeviceLocationSource {
  _FakeSource({
    required this.permission,
    this.grantedOnRequest,
    this.cached,
    this.current,
  });

  LocationAuthorization permission;
  final LocationAuthorization? grantedOnRequest;

  /// Mutable: el sistema actualiza su última posición conocida mientras la app
  /// está en el fondo (es justo lo que hace que la llegada se detecte).
  LocationFix? cached;
  final LocationFix? current;

  int requestCalls = 0;
  int currentFixCalls = 0;

  @override
  Future<LocationAuthorization> authorization() async => permission;

  @override
  Future<LocationAuthorization> requestAuthorization() async {
    requestCalls++;
    permission = grantedOnRequest ?? permission;
    return permission;
  }

  @override
  Future<LocationFix?> lastKnownFix() async => cached;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    currentFixCalls++;
    return current;
  }
}

class _MatchServiceStub implements MatchService {
  @override
  Future<Set<String>> fetchExcludedUids(String uid) async => const <String>{};

  @override
  Future<Set<String>> fetchDislikedUids(String uid) async => const <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}

class _ChatServiceStub implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}
