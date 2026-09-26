import 'dart:async';

import 'package:attra/src/features/ai_visual/data/ai_visual_service.dart';
import 'package:attra/src/features/auth/data/auth_service.dart';
import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/presentation/session_controller.dart';
import 'package:attra/src/features/auth/presentation/session_state.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/data/reply_suggestion_service.dart';
import 'package:attra/src/features/feed/data/ranking_signals_repository.dart';
import 'package:attra/src/features/geo/domain/travel_destination_resolver.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/onboarding/data/onboarding_repository.dart';
import 'package:attra/src/features/onboarding/data/voice_profile_service.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/settings/data/settings_repository.dart';
import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modo viaje en la sesión: situar el destino al activarlo y reparar los viajes
/// que se guardaron SIN centro (versiones anteriores de la app). Sin centro, el
/// feed de quien viajaba de Madrid a Cádiz no tenía desde dónde medir y se
/// quedaba con toda España, Madrid incluido.
void main() {
  late _AuthEvents auth;
  late _UserRepository users;
  late _Resolver resolver;
  late SessionController controller;

  setUp(() {
    auth = _AuthEvents();
    users = _UserRepository();
    resolver = _Resolver();
    controller = SessionController(
      authService: auth,
      userRepository: users,
      onboardingRepository: _UnusedOnboarding(),
      voiceProfileService: _UnusedVoice(),
      settingsRepository: _UnusedSettings(),
      entitlementService: _UnusedEntitlements(),
      featureFlagService: _UnusedFlags(),
      matchService: _UnusedMatches(),
      chatService: _UnusedChat(),
      profileSummaryRepository: _UnusedProfiles(),
      rankingSignalsRepository: _UnusedRanking(),
      storyService: _UnusedStories(),
      aiVisualService: _UnusedAi(),
      replySuggestionService: _UnusedSuggestions(),
      travelDestinationResolver: resolver,
    );
  });

  tearDown(() async {
    controller.dispose();
    await auth.events.close();
  });

  Future<void> signIn(String uid) async {
    final Completer<void> settled = Completer<void>();
    void onStateChanged() {
      if (controller.state.status != SessionStatus.loadingProfile &&
          !settled.isCompleted) {
        settled.complete();
      }
    }

    controller.addListener(onStateChanged);
    try {
      auth.events.add(_FirebaseUser(uid));
      await settled.future;
      expect(controller.state.status, SessionStatus.authenticated);
    } finally {
      controller.removeListener(onStateChanged);
    }
  }

  test('un viaje antiguo sin centro se repara UNA vez, sin tocar active/until',
      () async {
    users.current = _viajera(travelLat: null, travelLng: null);
    users.patched = Completer<void>();
    await signIn('yo');
    await users.patched!.future.timeout(const Duration(seconds: 2));

    expect(resolver.calls, <String>['ES|Cadiz|Spain']);
    expect(users.patches, hasLength(1));
    expect(users.patches.single.lat, closeTo(36.53, 1e-9));
    expect(users.patches.single.lng, closeTo(-6.29, 1e-9));
    expect(users.patches.single.source, TravelGeoSource.asset);
    // El centro se guarda con el destino para el que se resolvió.
    expect(users.patches.single.city, 'Cadiz');
    expect(users.patches.single.iso2, 'ES');
    expect(users.travelWrites, isEmpty,
        reason: 'la reparación solo añade el centro: ni reactiva ni alarga '
            'el viaje');

    // Una segunda entrada de la misma sesión no vuelve a gastar geocodificador.
    await controller.healTravelGeo(_viajera(travelLat: null, travelLng: null));
    expect(users.patches, hasLength(1));
  });

  test('si el viaje cambia mientras se resuelve, el centro viejo no se guarda',
      () async {
    // Carrera: la sesión empieza a situar Cádiz y, antes de que termine, el
    // viaje pasa a "España" sin ciudad. Antes solo se comprobaba el uid y el
    // centro de Cádiz caía sobre el viaje a un país entero.
    users.current = _viajera(travelLat: null, travelLng: null, travelCity: '');
    await signIn('yo');
    await pumpEventQueue();
    expect(resolver.calls, isEmpty, reason: 'un país entero no tiene centro');

    await controller.healTravelGeo(_viajera(travelLat: null, travelLng: null));
    expect(resolver.calls, hasLength(1));
    expect(users.patches, isEmpty);
  });

  test('si otro dispositivo ya lo situó, no se pisa', () async {
    users.current = _viajera(travelLat: 36.53, travelLng: -6.29);
    await signIn('yo');
    await controller.healTravelGeo(_viajera(travelLat: null, travelLng: null));
    expect(resolver.calls, hasLength(1));
    expect(users.patches, isEmpty);
  });

  test('quien no viaja (o ya tiene centro) no dispara nada', () async {
    users.current = _viajera(travelLat: 36.53, travelLng: -6.29);
    await signIn('yo');
    await pumpEventQueue();
    expect(resolver.calls, isEmpty);
    expect(users.patches, isEmpty);

    await controller.healTravelGeo(_viajera(
      travelLat: null,
      travelLng: null,
      travelActive: false,
    ));
    expect(resolver.calls, isEmpty);
  });

  test('activar un viaje sitúa la ciudad ANTES de guardarlo', () async {
    users.current = _viajera(travelLat: 36.53, travelLng: -6.29);
    await signIn('yo');

    final TravelApplyResult result = await controller.setTravelLocation(
      active: true,
      iso2: 'ES',
      city: 'Cadiz',
      country: 'Spain',
    );
    expect(result.located, isTrue);
    final _TravelWrite w = users.travelWrites.single;
    expect(w.active, isTrue);
    expect(w.lat, closeTo(36.53, 1e-9));
    expect(w.lng, closeTo(-6.29, 1e-9));
    expect(w.source, TravelGeoSource.asset);
  });

  test('una ciudad que no se puede situar se guarda igual y se avisa',
      () async {
    users.current = _viajera(travelLat: 36.53, travelLng: -6.29);
    await signIn('yo');
    resolver.found = false;

    final TravelApplyResult result = await controller.setTravelLocation(
      active: true,
      iso2: 'ES',
      city: 'Villanueva',
      country: 'Spain',
    );
    expect(result.located, isFalse);
    expect(users.travelWrites.single.lat, isNull);
    expect(users.travelWrites.single.source, TravelGeoSource.none);
  });

  test('a un país entero o al apagar: sin centro y sin preguntar', () async {
    users.current = _viajera(travelLat: 36.53, travelLng: -6.29);
    await signIn('yo');

    final TravelApplyResult pais = await controller.setTravelLocation(
        active: true, iso2: 'ES', country: 'Spain');
    final TravelApplyResult apagar = await controller.setTravelLocation(
        active: false, iso2: 'ES', city: 'Cadiz', country: 'Spain');
    expect(pais.located, isTrue, reason: 'sin ciudad no es un fallo');
    expect(apagar.located, isTrue);
    expect(resolver.calls, isEmpty);
    expect(users.travelWrites.map((_TravelWrite w) => w.lat), <Object?>[
      null,
      null,
    ]);
  });

  test('discovery se consulta por el país de casa y el de destino', () {
    expect(SessionController.discoveryCountriesFor(_viajera()), <String>{'ES'});
    expect(
        SessionController.discoveryCountriesFor(_viajera(
          travelIso2: 'IT',
          countryIso2: '',
          countryName: 'Spain',
        )),
        <String>{'ES', 'IT'},
        reason: 'sin ISO2 guardado se deduce del nombre si es conocido');
    expect(
        SessionController.discoveryCountriesFor(_viajera(
          travelActive: false,
          travelIso2: 'IT',
        )),
        <String>{'ES'});
    expect(
        SessionController.discoveryCountriesFor(_viajera(
          countryIso2: '',
          countryName: 'Narnia',
          travelActive: false,
        )),
        isEmpty,
        reason: 'sin país conocido queda solo la consulta antigua');
  });
}

AppUser _viajera({
  double? travelLat = 36.53,
  double? travelLng = -6.29,
  bool travelActive = true,
  String travelIso2 = 'ES',
  String countryIso2 = 'ES',
  String countryName = 'España',
  String travelCity = 'Cadiz',
}) {
  return AppUser(
    uid: 'yo',
    email: null,
    displayName: 'Yo',
    photoUrl: null,
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    countryName: countryName,
    countryIso2: countryIso2,
    travelActive: travelActive,
    travelIso2: travelIso2,
    travelCity: travelCity,
    travelCountry: 'Spain',
    travelUntil: DateTime.now().add(const Duration(days: 20)),
    travelLat: travelLat,
    travelLng: travelLng,
  );
}

class _Resolver implements TravelDestinationResolver {
  bool found = true;
  final List<String> calls = <String>[];

  @override
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  }) async {
    calls.add('$iso2|$city|$countryName');
    if (!found) return null;
    return const TravelDestination(
      latitude: 36.53,
      longitude: -6.29,
      source: TravelGeoSource.asset,
    );
  }
}

class _TravelWrite {
  const _TravelWrite(this.active, this.lat, this.lng, this.source);
  final bool active;
  final double? lat;
  final double? lng;
  final TravelGeoSource source;
}

class _UnexpectedCalls {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Llamada inesperada: ${invocation.memberName}');
}

class _AuthEvents extends _UnexpectedCalls implements AuthService {
  final StreamController<User?> events = StreamController<User?>();

  @override
  Stream<User?> get authStateChanges => events.stream;
}

class _FirebaseUser extends _UnexpectedCalls implements User {
  _FirebaseUser(this.uid);

  @override
  final String uid;
}

class _UserRepository extends _UnexpectedCalls implements UserRepository {
  late AppUser current;
  Completer<void>? patched;
  final List<
      ({
        double lat,
        double lng,
        TravelGeoSource source,
        String city,
        String iso2,
      })> patches = <({
    double lat,
    double lng,
    TravelGeoSource source,
    String city,
    String iso2,
  })>[];
  final List<_TravelWrite> travelWrites = <_TravelWrite>[];

  @override
  Future<UserSyncResult> syncUserFromAuth(User firebaseUser) async =>
      UserSyncResult(user: current, isNewUser: false);

  @override
  Future<AppUser> fetchByUid(String uid) async => current;

  @override
  Future<bool> hasAcceptedCurrentTerms(String uid) async => true;

  @override
  Future<void> patchTravelGeo({
    required String uid,
    required double latitude,
    required double longitude,
    required TravelGeoSource source,
    required String city,
    required String iso2,
  }) async {
    patches.add((
      lat: latitude,
      lng: longitude,
      source: source,
      city: city,
      iso2: iso2,
    ));
    patched?.complete();
  }

  @override
  Future<void> setTravelLocation({
    required String uid,
    required bool active,
    String iso2 = '',
    String city = '',
    String country = '',
    double? latitude,
    double? longitude,
    TravelGeoSource geoSource = TravelGeoSource.none,
  }) async {
    travelWrites.add(_TravelWrite(active, latitude, longitude, geoSource));
  }
}

// Estos servicios no participan en el modo viaje. Una llamada accidental falla
// para evitar dependencia de Firebase o la red.
class _UnusedOnboarding extends _UnexpectedCalls
    implements OnboardingRepository {}

class _UnusedSuggestions extends _UnexpectedCalls
    implements ReplySuggestionService {}

class _UnusedVoice extends _UnexpectedCalls implements VoiceProfileService {}

class _UnusedSettings extends _UnexpectedCalls implements SettingsRepository {}

class _UnusedEntitlements extends _UnexpectedCalls
    implements EntitlementService {}

class _UnusedFlags extends _UnexpectedCalls implements FeatureFlagService {}

class _UnusedMatches extends _UnexpectedCalls implements MatchService {}

class _UnusedChat extends _UnexpectedCalls implements ChatService {}

class _UnusedProfiles extends _UnexpectedCalls
    implements ProfileSummaryRepository {}

class _UnusedRanking extends _UnexpectedCalls
    implements RankingSignalsRepository {}

class _UnusedStories extends _UnexpectedCalls implements StoryService {}

class _UnusedAi extends _UnexpectedCalls implements AiVisualService {}
