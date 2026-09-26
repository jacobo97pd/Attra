import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/geo/data/geo_repository.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// LA QUEJA DEL USUARIO, con el feed de verdad montado: "estoy en Madrid, pongo
/// el modo viaje en Cádiz y sigo viendo gente de Madrid".
///
/// Viajando, el feed se quedaba solo con la regla de país (toda España), el
/// ranking medía la cercanía desde las coordenadas REALES (Madrid arriba) y la
/// ordenación por ciudad se hacía antes del ranking, que la deshacía. Aquí se
/// recorre el mazo entero, carta a carta, y se comprueba qué sale y en qué
/// orden, tanto con el viaje guardado CON centro (versión nueva) como SIN él
/// (viaje guardado por una versión anterior de la app).
void main() {
  // Pool de la queja: gente de Madrid (con y sin ubicación), de Barcelona, de
  // Cádiz (con y sin ubicación) y de Jerez, a 15 km del centro de Cádiz.
  final List<SeedProfile> pool = <SeedProfile>[
    _perfil('madrid_geo', 'Mario', city: 'Madrid', lat: 40.42, lng: -3.70),
    _perfil('madrid_sin_geo', 'Manu', city: 'Madrid'),
    _perfil('barcelona', 'Bruno', city: 'Barcelona', lat: 41.39, lng: 2.17),
    _perfil('jerez', 'Javi',
        city: 'Jerez de la Frontera', lat: 36.69, lng: -6.14),
    _perfil('lucia', 'Lucas', city: 'Cádiz', lat: 36.53, lng: -6.29),
    _perfil('cadiz_sin_geo', 'Carlos', city: 'Cadiz'),
  ];

  testWidgets('viaje CON centro: primero Cádiz, luego Jerez y nadie de Madrid',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_host(
      user: _viajera(travelLat: 36.53, travelLng: -6.29),
      profiles: pool,
      travelPlanActive: true,
    ));
    await tester.pumpAndSettle();

    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, isNot(contains('Mario')), reason: 'Madrid con ubicación');
    expect(mazo, isNot(contains('Manu')), reason: 'Madrid sin ubicación');
    expect(mazo, isNot(contains('Bruno')), reason: 'Barcelona');
    expect(mazo.take(2), unorderedEquals(<String>['Lucas', 'Carlos']),
        reason: 'la gente de la ciudad de destino va primero');
    expect(mazo, <String>[...mazo.take(2), 'Javi']);
  });

  testWidgets('viaje SIN centro guardado (app antigua): igual, con el dataset',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // El dataset offline se lee de verdad (sin él, el viaje antiguo se quedaba
    // en "toda España"). Se precarga fuera del reloj falso del test porque los
    // ficheros grandes se decodifican en otro isolate.
    await tester
        .runAsync(() => GeoRepository.instance.cityCoordinates('ES', 'Cadiz'));
    await tester.pumpWidget(_host(
      user: _viajera(travelLat: null, travelLng: null),
      profiles: pool,
      travelPlanActive: true,
    ));
    await tester.pumpAndSettle();

    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, isNot(contains('Mario')));
    expect(mazo, isNot(contains('Manu')));
    expect(mazo, isNot(contains('Bruno')));
    expect(mazo.take(2), unorderedEquals(<String>['Lucas', 'Carlos']));
    expect(mazo, contains('Javi'));
  });

  testWidgets('con el plan caducado el viaje no cuenta: feed de casa y aviso',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_host(
      user: _viajera(travelLat: 36.53, travelLng: -6.29),
      profiles: pool,
      travelPlanActive: false,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modo viajes en pausa'), findsOneWidget);
    expect(find.textContaining('De viaje en'), findsNothing);
    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, contains('Mario'),
        reason: 'el backend ya lo publica en casa: su feed también es el de '
            'casa (si no, vería a gente de Cádiz que no le puede ver)');
    expect(mazo, isNot(contains('Lucas')));
  });

  testWidgets('entitlements aún cargando: el viaje cuenta (sin feed de casa)',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // El controlador arranca como Free: sin esta tolerancia, todo viajero de
    // pago veía un instante a la gente de Madrid al abrir la app.
    await tester.pumpWidget(_host(
      user: _viajera(travelLat: 36.53, travelLng: -6.29),
      profiles: pool,
      travelPlanActive: false,
      entitlementsLoading: true,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modo viajes en pausa'), findsNothing);
    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, isNot(contains('Mario')));
    expect(mazo.first, anyOf('Lucas', 'Carlos'));
  });

  testWidgets('un viaje caducado se avisa y se pide apagarlo', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    int apagados = 0;
    await tester.pumpWidget(_host(
      user: _viajera(
        travelLat: 36.53,
        travelLng: -6.29,
        travelUntil: DateTime.now().subtract(const Duration(days: 1)),
      ),
      profiles: pool,
      travelPlanActive: true,
      onTravelExpired: () async => apagados++,
    ));
    await tester.pumpAndSettle();

    expect(apagados, 1,
        reason: 'sin esto el documento seguía con active=true y la ficha '
            'pública podía seguir en el destino');
    expect(
        find.textContaining('Tu viaje a Cadiz ha terminado'), findsOneWidget);
    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, contains('Mario'), reason: 'vuelve el feed de casa');
  });

  testWidgets(
      'feed de casa en Madrid: no sale quien viaja a Cádiz publicado sin '
      'centro', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    // Caso D02 tras el despliegue: alguien con la app ANTIGUA en Madrid activa
    // un viaje a Cádiz sin lat/lng y el backend lo publica "de viaje" en
    // España SIN `geo`. Sin coordenadas se saltaba el radio de quien mira y
    // salía, "De viaje", a toda la gente de Madrid.
    await tester.pumpWidget(_host(
      user: _madrilena(),
      profiles: <SeedProfile>[
        ...pool,
        _perfil('viajero_cadiz', 'Tomás', city: 'Cádiz', traveling: true),
        _perfil('viajero_madrid', 'Toni', city: 'Madrid', traveling: true),
      ],
      travelPlanActive: false,
    ));
    await tester.pumpAndSettle();

    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, isNot(contains('Tomás')),
        reason: 'de viaje en Cádiz y sin centro: no se puede medir, y desde '
            'Madrid no es "de tu zona"');
    expect(mazo, contains('Toni'),
        reason: 'quien viaja a TU ciudad sí sale, aunque no tenga centro');
    expect(mazo, containsAll(<String>['Mario', 'Manu']),
        reason: 'las fichas normales (con o sin ubicación) no cambian');
    expect(mazo, isNot(contains('Lucas')), reason: 'Cádiz, fuera del radio');
  });
}

/// Quien mira desde casa: vive en Madrid, no viaja.
AppUser _madrilena() {
  return AppUser(
    uid: 'yo',
    email: 'yo@example.test',
    displayName: 'Yo',
    photoUrl: '',
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    gender: 'female',
    interestedIn: const <String>['male'],
    latitude: 40.4168,
    longitude: -3.7038,
    locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    countryName: 'España',
    countryIso2: 'ES',
    city: 'Madrid',
    maxDistanceKm: 100,
  );
}

AppUser _viajera({
  required double? travelLat,
  required double? travelLng,
  DateTime? travelUntil,
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
    gender: 'female',
    interestedIn: const <String>['male'],
    // Ubicación REAL: Madrid, reciente. Nunca debe usarse viajando.
    latitude: 40.4168,
    longitude: -3.7038,
    locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    countryName: 'España',
    countryIso2: 'ES',
    travelActive: true,
    travelIso2: 'ES',
    // Grafía del dataset (lo que guarda el selector), sin acento.
    travelCity: 'Cadiz',
    travelCountry: 'Spain',
    travelUntil: travelUntil ?? DateTime.now().add(const Duration(days: 20)),
    travelLat: travelLat,
    travelLng: travelLng,
  );
}

SeedProfile _perfil(
  String id,
  String nombre, {
  required String city,
  double? lat,
  double? lng,
  bool traveling = false,
}) {
  return SeedProfile.fromMap(id, <String, dynamic>{
    'displayName': nombre,
    'age': 30,
    'currentCity': city,
    'currentCountryName': 'España',
    'countryIso2': 'ES',
    'gender': 'male',
    'interestedIn': <String>['female'],
    'isBot': false,
    'bio': 'Hola',
    if (traveling) 'traveling': true,
    if (lat != null && lng != null)
      'geo': <String, dynamic>{'lat': lat, 'lng': lng},
  });
}

Widget _host({
  required AppUser user,
  required List<SeedProfile> profiles,
  required bool travelPlanActive,
  bool entitlementsLoading = false,
  Future<void> Function()? onTravelExpired,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: FeedScreen(
        user: user,
        onLoadSeedProfiles: () async => profiles,
        matchService: _MatchServiceStub(),
        chatService: _ChatServiceStub(),
        locationSource: _SinGps(),
        onDeviceLocation: _noGuardar,
        placeResolver: const _SinSitio(),
        travelPlanActive: travelPlanActive,
        entitlementsLoading: entitlementsLoading,
        onTravelExpired: onTravelExpired,
      ),
    ),
  );
}

/// Nombres de todo el mazo, en orden: pasa carta a carta hasta agotarlo.
Future<List<String>> _recorrerMazo(WidgetTester tester) async {
  final List<String> vistos = <String>[];
  final Finder carta = find.byKey(const ValueKey<String>('feed-swipe-card'));
  for (int i = 0; i < 20 && carta.evaluate().isNotEmpty; i++) {
    final String quien = _quien(tester);
    if (quien.isEmpty) break;
    vistos.add(quien);
    await tester.drag(carta, const Offset(-260, 0));
    await tester.pumpAndSettle();
  }
  return vistos;
}

/// Nombre de quien está en la tarjeta (la ficha lo pinta como «Lucas, 30»).
String _quien(WidgetTester tester) {
  for (final Text texto in tester.widgetList<Text>(find.byType(Text))) {
    final String data = texto.data ?? '';
    if (data.endsWith(', 30')) return data.substring(0, data.length - 4);
  }
  return '';
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _noGuardar({
  required double latitude,
  required double longitude,
  required DateTime fixedAt,
  String? permissionStatus,
  bool? permissionGranted,
  ResolvedPlace? place,
}) async {}

class _SinSitio implements PlaceResolver {
  const _SinSitio();

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async =>
      null;
}

/// Permiso concedido pero sin lecturas: el test va de a quién se ve, no del
/// GPS (eso lo cubre feed_location_refresh_test).
class _SinGps implements DeviceLocationSource {
  @override
  Future<LocationAuthorization> authorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationAuthorization> requestAuthorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationFix?> lastKnownFix() async => null;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      null;
}

class _MatchServiceStub implements MatchService {
  @override
  Future<Set<String>> fetchExcludedUids(String uid) async => const <String>{};

  @override
  Future<Set<String>> fetchDislikedUids(String uid) async => const <String>{};

  @override
  Future<void> passProfile(String toUid) async {}

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
