import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/feed/domain/ranking.dart';
import 'package:attra/src/features/feed/domain/ranking_config.dart';
import 'package:attra/src/features/feed/domain/travel_scope.dart';
import 'package:attra/src/features/geo/domain/place_names.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/premium_feature.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// EL BUG QUE REPORTÓ EL USUARIO: "Estoy en Madrid, pongo el modo viaje en
/// Cádiz y sigo viendo gente de Madrid".
///
/// Viajando, el feed descartaba las coordenadas y se quedaba solo con la regla
/// de país (toda España), el ranking medía la cercanía desde las coordenadas
/// REALES (Madrid arriba) y la ordenación por ciudad se aplicaba antes del
/// ranking, que la deshacía.
void main() {
  const double madridLat = 40.4168;
  const double madridLng = -3.7038;
  const double cadizLat = 36.53;
  const double cadizLng = -6.29;

  AppUser viajera({
    double? travelLat = cadizLat,
    double? travelLng = cadizLng,
    int? maxDistanceKm,
    String travelCity = 'Cadiz',
  }) =>
      AppUser(
        uid: 'yo',
        email: null,
        displayName: 'Yo',
        photoUrl: null,
        onboardingCompleted: true,
        profileCompleted: true,
        profileCompletionPercent: 100,
        isBot: false,
        gender: 'female',
        interestedIn: const <String>['male'],
        // Coordenadas REALES: Madrid. Nunca deben usarse viajando.
        latitude: madridLat,
        longitude: madridLng,
        countryName: 'España',
        countryIso2: 'ES',
        maxDistanceKm: maxDistanceKm,
        travelActive: true,
        travelIso2: 'ES',
        travelCity: travelCity,
        travelCountry: 'Spain',
        travelUntil: DateTime.now().add(const Duration(days: 20)),
        travelLat: travelLat,
        travelLng: travelLng,
      );

  SeedProfile perfil(
    String id, {
    required String city,
    double? lat,
    double? lng,
    String country = 'España',
    String iso2 = 'ES',
  }) =>
      SeedProfile.fromMap(id, <String, dynamic>{
        'displayName': id,
        'currentCity': city,
        'currentCountryName': country,
        if (iso2.isNotEmpty) 'countryIso2': iso2,
        'gender': 'male',
        'interestedIn': <String>['female'],
        'isBot': false,
        'photoUrl': 'https://example.test/$id.jpg',
        if (lat != null && lng != null)
          'geo': <String, dynamic>{'lat': lat, 'lng': lng},
      });

  final List<SeedProfile> pool = <SeedProfile>[
    perfil('madrid_geo', city: 'Madrid', lat: 40.42, lng: -3.70),
    perfil('madrid_sin_geo', city: 'Madrid'),
    perfil('lucia_cadiz', city: 'Cádiz', lat: 36.53, lng: -6.29),
    perfil('jerez', city: 'Jerez de la Frontera', lat: 36.69, lng: -6.14),
    perfil('barcelona', city: 'Barcelona', lat: 41.39, lng: 2.17),
    perfil('cadiz_sin_geo', city: 'Cadiz'),
  ];

  ({List<SeedProfile> profiles, bool widened}) filtrar(
    FeedOrigin origin, {
    List<SeedProfile>? profiles,
  }) =>
      TravelScope.filter(
        origin: origin,
        profiles: profiles ?? pool,
        myUid: 'yo',
        myGender: 'female',
        myInterestedIn: const <String>['male'],
        excludedUids: const <String>{},
      );

  test('Madrid → Cádiz: nadie de Madrid ni de Barcelona, Cádiz primero', () {
    final AppUser me = viajera();
    final FeedOrigin origin = TravelScope.resolve(me, travelAllowed: true)!;
    expect(origin.lat, cadizLat, reason: 'el centro es el destino, no Madrid');

    final List<SeedProfile> filtered = filtrar(origin).profiles;
    final List<String> ids =
        filtered.map((SeedProfile p) => p.id).toList(growable: false);
    expect(ids, isNot(contains('madrid_geo')));
    expect(ids, isNot(contains('madrid_sin_geo')),
        reason: 'sin coordenadas solo entra quien dice estar en el destino');
    expect(ids, isNot(contains('barcelona')));
    expect(ids, containsAll(<String>['lucia_cadiz', 'cadiz_sin_geo', 'jerez']));

    // Ranking desde el destino y, DESPUÉS, la gente de Cádiz delante.
    final List<SeedProfile> ranked = RankingScorer.rank(
      profiles: filtered,
      me: me,
      config: const RankingConfig(),
      diversify: false,
      origin: origin.rankingOrigin,
      jitterSeed: 7,
    );
    final List<String> finalIds = TravelScope.destinationFirst(ranked, origin)
        .map((SeedProfile p) => p.id)
        .toList(growable: false);
    expect(finalIds.take(2),
        unorderedEquals(<String>['lucia_cadiz', 'cadiz_sin_geo']));
    expect(finalIds.last, 'jerez');
  });

  test('ciudades comparadas sin acentos ni idioma', () {
    expect(PlaceNames.canonCity('Cadiz'), PlaceNames.canonCity('Cádiz'));
    expect(PlaceNames.canonCity('El Puerto de Santa María'),
        PlaceNames.canonCity('El Puerto de Santa Maria'));
    expect(PlaceNames.canonCity('Roma'), PlaceNames.canonCity('Rome'));
    expect(PlaceNames.canonCity('Lisboa'), PlaceNames.canonCity('Lisbon'));
  });

  test('radio viajando: nunca menos de 20 km', () {
    expect(
        TravelScope.resolve(viajera(maxDistanceKm: 2), travelAllowed: true)!
            .radiusKm,
        TravelScope.minTravelRadiusKm);
    expect(
        TravelScope.resolve(viajera(maxDistanceKm: 80), travelAllowed: true)!
            .radiusKm,
        80);
    expect(TravelScope.resolve(viajera(), travelAllowed: true)!.radiusKm, 100);
  });

  test('vacío alrededor del destino: amplía UNA vez a 250 km, nunca a Madrid',
      () {
    final FeedOrigin origin =
        TravelScope.resolve(viajera(maxDistanceKm: 2), travelAllowed: true)!;
    final List<SeedProfile> lejos = <SeedProfile>[
      perfil('sevilla', city: 'Sevilla', lat: 37.39, lng: -5.98),
      perfil('madrid_geo', city: 'Madrid', lat: 40.42, lng: -3.70),
    ];
    final ({List<SeedProfile> profiles, bool widened}) r =
        filtrar(origin, profiles: lejos);
    expect(r.widened, isTrue);
    expect(r.profiles.map((SeedProfile p) => p.id), <String>['sevilla']);
    // Con gente cerca no se amplía.
    expect(filtrar(origin).widened, isFalse);
  });

  test('destino sin centro: solo el país de destino y la ciudad delante', () {
    final FeedOrigin origin = TravelScope.resolve(
      viajera(travelLat: null, travelLng: null),
      travelAllowed: true,
    )!;
    expect(origin.hasCoordinates, isFalse);
    final List<SeedProfile> extranjero = <SeedProfile>[
      ...pool,
      perfil('lisboa',
          city: 'Lisboa',
          lat: 38.72,
          lng: -9.14,
          country: 'Portugal',
          iso2: 'PT'),
    ];
    final List<SeedProfile> filtered =
        filtrar(origin, profiles: extranjero).profiles;
    expect(filtered.map((SeedProfile p) => p.id), isNot(contains('lisboa')));
    expect(filtered.length, pool.length);

    // Cercanía NEUTRA: sin centro no se mide desde casa (Madrid no gana).
    final List<RankedProfile> scored = RankingScorer.score(
      profiles: filtered,
      me: viajera(travelLat: null, travelLng: null),
      origin: origin.rankingOrigin,
    );
    for (final RankedProfile r in scored) {
      expect(r.breakdown.proximity, 0.5, reason: r.profile.id);
    }
    final List<String> ids = TravelScope.destinationFirst(filtered, origin)
        .map((SeedProfile p) => p.id)
        .toList(growable: false);
    expect(
        ids.take(2), unorderedEquals(<String>['lucia_cadiz', 'cadiz_sin_geo']));
  });

  test('un viaje antiguo sin centro se centra con el del dataset', () {
    final FeedOrigin origin = TravelScope.resolve(
      viajera(travelLat: null, travelLng: null),
      travelAllowed: true,
      fallbackCenter: (lat: cadizLat, lng: cadizLng),
    )!;
    expect(origin.hasCoordinates, isTrue);
    expect(filtrar(origin).profiles.map((SeedProfile p) => p.id),
        isNot(contains('madrid_geo')));
  });

  test('sin plan que lo incluya (y cargado) el viaje no cuenta', () {
    expect(TravelScope.resolve(viajera(), travelAllowed: false), isNull);
    expect(TravelScope.isTravelEffective(viajera(), travelAllowed: false),
        isFalse);
    expect(
        TravelScope.isTravelEffective(viajera(), travelAllowed: true), isTrue);
  });

  group('gate del viaje = el del backend (isPaidActive), no los flags', () {
    final DateTime ahora = DateTime(2026, 9, 26, 12);
    final UserEntitlements pro = UserEntitlements.forTier(
      uid: 'yo',
      tier: SubscriptionTier.pro,
      expiresAt: ahora.add(const Duration(days: 10)),
    );

    test('IA apagada por emergencia: el viaje de un Pro sigue contando', () {
      // Es la palanca de emergencia de la IA. Antes apagaba el tier Pro entero
      // y todo viajero Pro volvía a su casa mientras el backend le seguía
      // publicando en el destino. Viajar no es IA: ni la hoja ni el feed
      // deben enterarse de que la IA está apagada.
      const MonetizationFeatureFlags iaApagada =
          MonetizationFeatureFlags(aiKillSwitch: true);
      expect(
          pro.hasFeature(PremiumFeature.travelMode,
              flags: iaApagada, at: ahora),
          isTrue,
          reason: 'la palanca de la IA solo apaga funciones de IA');
      expect(TravelScope.planKeepsTravel(pro, now: ahora), isTrue,
          reason: 'y el viaje puesto sigue, como en el backend');
    });

    test('monetización apagada: igual, manda el plan', () {
      const MonetizationFeatureFlags sinMonetizacion =
          MonetizationFeatureFlags(monetizationEnabled: false);
      expect(
          pro.hasFeature(PremiumFeature.travelMode,
              flags: sinMonetizacion, at: ahora),
          isFalse);
      expect(TravelScope.planKeepsTravel(pro, now: ahora), isTrue);
    });

    test('plan caducado, Free o sin datos: no cuenta', () {
      final UserEntitlements caducado = UserEntitlements.forTier(
        uid: 'yo',
        tier: SubscriptionTier.plus,
        expiresAt: ahora.subtract(const Duration(days: 1)),
      );
      expect(TravelScope.planKeepsTravel(caducado, now: ahora), isFalse);
      expect(
          TravelScope.planKeepsTravel(UserEntitlements.free(uid: 'yo'),
              now: ahora),
          isFalse);
      expect(TravelScope.planKeepsTravel(null, now: ahora), isFalse);
    });

    test('vitalicio (cuentas de App Review): cuenta sin fecha de fin', () {
      final UserEntitlements vitalicio = UserEntitlements.forTier(
        uid: 'yo',
        tier: SubscriptionTier.pro,
        isLifetime: true,
      );
      expect(TravelScope.planKeepsTravel(vitalicio, now: ahora), isTrue);
    });
  });
}
