import 'dart:math' as math;

import '../../auth/domain/app_user.dart';
import '../../auth/domain/location_refresh_policy.dart';
import '../../geo/domain/place_names.dart';
import '../../monetization/domain/user_entitlements.dart';
import '../../profile/domain/profile_state.dart';
import '../../social/domain/intent_mode.dart';
import 'feed_filter.dart';
import 'feed_filters.dart';
import 'ranking.dart';

/// Punto de referencia del feed mientras se viaja: el CENTRO de la ciudad de
/// destino, el país de destino y el radio. Nunca lleva la ubicación real.
class FeedOrigin {
  const FeedOrigin({
    required this.lat,
    required this.lng,
    required this.countryIso2,
    required this.countryName,
    required this.city,
    required this.radiusKm,
  });

  /// Centro del destino. null = viaje sin coordenadas (a un país entero, o
  /// una ciudad que no se pudo situar): el feed se queda en el país.
  final double? lat;
  final double? lng;
  final String countryIso2;
  final String countryName;
  final String city;
  final int radiusKm;

  bool get hasCoordinates => lat != null && lng != null;

  /// Cercanía del ranking medida desde el destino (neutra si no hay centro).
  RankingOrigin get rankingOrigin => RankingOrigin(lat: lat, lng: lng);
}

/// El modo viaje como Tinder Passport: el feed se centra en el destino con el
/// radio del usuario, primero la gente de la ciudad de destino y NUNCA desde
/// las coordenadas de casa.
///
/// Por qué existe: viajando, el feed descartaba la latitud/longitud y se
/// quedaba solo con la regla de país. Quien estaba en Madrid y viajaba a Cádiz
/// veía a TODA España, con Madrid arriba (el ranking medía la cercanía desde
/// casa) y la ordenación por ciudad deshecha después por el ranking.
class TravelScope {
  const TravelScope._();

  /// Radio mínimo viajando. El centro es el de la ciudad, no un fix de GPS, y
  /// el selector de distancia baja hasta 1 km: con 2 km alrededor del centro
  /// de Cádiz no salía casi nadie de la propia ciudad.
  static const int minTravelRadiusKm = 20;

  /// Un único escalón de ampliación cuando alrededor del destino no hay nadie.
  /// Nunca se amplía a todo el país ni se vuelve a las coordenadas de casa.
  static const int widenedRadiusKm = 250;

  /// A esta distancia del centro (o con la misma ciudad) se cuenta como "de la
  /// ciudad de destino" para ponerle delante.
  static const double destinationCityKm = 15;

  /// ¿Cuenta el viaje para el feed? Es una función de PAGO: con el plan
  /// caducado el backend ya publica al usuario en su casa, así que su feed no
  /// puede seguir en el destino (vería a gente que no le puede ver).
  ///
  /// [travelAllowed] = el plan sigue siendo de pago ([planKeepsTravel]) o los
  /// entitlements aún no han cargado: al arrancar el controlador es Free y,
  /// sin esa tolerancia, todo viajero de pago veía un instante el feed de casa
  /// (y se disparaba una recarga y un refresco de ubicación para nada).
  static bool isTravelEffective(AppUser? user, {required bool travelAllowed}) =>
      user != null && user.isTraveling && travelAllowed;

  /// ¿Sigue el plan sosteniendo un viaje YA activado? Es la misma condición
  /// que usa el backend para publicar al viajero en el destino (`isPaidActive`
  /// en functions/src/discovery.ts): tier de pago y sin caducar. Nada más.
  ///
  /// A propósito NO pasa por `hasFeature`/`canUseTravelMode`: esos miran los
  /// flags de monetización, y para Pro también los interruptores de la IA
  /// (`aiKillSwitch`, `proAiEnabled`). El backend no los mira y sigue
  /// publicando al viajero en el destino, así que apagar la IA en una
  /// emergencia devolvía el feed de todo viajero Pro a su casa: él seguía
  /// "de viaje en Cádiz" para los demás y veía gente que no le podía ver
  /// (la visibilidad de un solo sentido que este gate venía a quitar). Los
  /// flags deciden si se puede ACTIVAR un viaje (la hoja), no si uno ya
  /// activo sigue contando.
  static bool planKeepsTravel(UserEntitlements? entitlements, {DateTime? now}) {
    if (entitlements == null) return false;
    return entitlements.effectiveTierAt(now ?? DateTime.now()).isPaid;
  }

  /// Radio viajando: el del usuario (filtro o preferencia) con suelo en
  /// [minTravelRadiusKm].
  static int travelRadiusKm({int? filterMaxKm, int? userMaxKm}) => math.max(
        filterMaxKm ?? userMaxKm ?? FeedFilter.defaultRadiusKm,
        minTravelRadiusKm,
      );

  /// Origen del feed viajando, o null si no se viaja (o no cuenta).
  ///
  /// [fallbackCenter] es el centro resuelto al vuelo (dataset offline) para
  /// viajes guardados SIN coordenadas por versiones anteriores: así el primer
  /// feed ya es el bueno sin esperar a que la sesión los repare.
  static FeedOrigin? resolve(
    AppUser? user, {
    required bool travelAllowed,
    int? filterMaxKm,
    ({double lat, double lng})? fallbackCenter,
  }) {
    if (user == null ||
        !isTravelEffective(user, travelAllowed: travelAllowed)) {
      return null;
    }
    final bool hasCity = user.travelCity.trim().isNotEmpty;
    final double? lat = user.hasTravelOrigin
        ? user.travelLat
        : (hasCity ? fallbackCenter?.lat : null);
    final double? lng = user.hasTravelOrigin
        ? user.travelLng
        : (hasCity ? fallbackCenter?.lng : null);
    return FeedOrigin(
      lat: lat,
      lng: lng,
      countryIso2: user.travelIso2.trim().toUpperCase(),
      countryName: user.travelCountry.trim(),
      city: user.travelCity.trim(),
      radiusKm: travelRadiusKm(
        filterMaxKm: filterMaxKm,
        userMaxKm: user.maxDistanceKm,
      ),
    );
  }

  /// Filtra el pool para el viaje. Devuelve también si hubo que AMPLIAR el
  /// radio (para contárselo al usuario en un banner).
  ///
  /// - Con centro: radio alrededor del destino y, sin coordenadas, solo quien
  ///   dice estar en la ciudad de destino. Si no queda nadie, un escalón a
  ///   [widenedRadiusKm].
  /// - Sin centro: solo país de destino (sin radio que medir).
  static ({List<SeedProfile> profiles, bool widened}) filter({
    required FeedOrigin origin,
    required List<SeedProfile> profiles,
    required String myUid,
    required String myGender,
    required List<String> myInterestedIn,
    required Set<String> excludedUids,
    FeedFilters filters = const FeedFilters(),
    IntentMode myIntent = IntentMode.dating,
  }) {
    List<SeedProfile> run(int? radiusKm) => FeedFilter.apply(
          profiles: profiles,
          myUid: myUid,
          myGender: myGender,
          myInterestedIn: myInterestedIn,
          excludedUids: excludedUids,
          filters: filters,
          myLat: origin.lat,
          myLng: origin.lng,
          myCountry: origin.countryName,
          myCountryIso2: origin.countryIso2,
          maxKmOverride: radiusKm,
          noGeoCity: origin.hasCoordinates ? origin.city : '',
          myIntent: myIntent,
        );

    if (!origin.hasCoordinates) {
      return (profiles: run(null), widened: false);
    }
    final List<SeedProfile> near = run(origin.radiusKm);
    if (near.isNotEmpty || origin.radiusKm >= widenedRadiusKm) {
      return (profiles: near, widened: false);
    }
    final List<SeedProfile> wide = run(widenedRadiusKm);
    return (profiles: wide, widened: wide.isNotEmpty);
  }

  /// ¿Es de la ciudad de destino? Misma ciudad (sin acentos ni idioma:
  /// 'Cadiz' = 'Cádiz') o a menos de [destinationCityKm] del centro.
  static bool isInDestinationCity(SeedProfile p, FeedOrigin origin) {
    final String city = PlaceNames.canonCity(origin.city);
    if (city.isNotEmpty && PlaceNames.canonCity(p.city) == city) return true;
    if (origin.hasCoordinates && p.lat != null && p.lng != null) {
      return LocationRefreshPolicy.distanceKm(
              origin.lat!, origin.lng!, p.lat!, p.lng!) <=
          destinationCityKm;
    }
    return false;
  }

  /// Partición ESTABLE: primero la gente de la ciudad de destino, luego el
  /// resto, cada grupo en el orden en que ya venía (ranking, Slow Dating).
  ///
  /// Va DESPUÉS del ranking a propósito: la ordenación por ciudad que había
  /// antes se aplicaba antes y el ranking (y la diversificación por ciudad)
  /// la deshacían.
  static List<SeedProfile> destinationFirst(
    List<SeedProfile> ranked,
    FeedOrigin origin,
  ) {
    final List<SeedProfile> first = <SeedProfile>[];
    final List<SeedProfile> rest = <SeedProfile>[];
    for (final SeedProfile p in ranked) {
      (isInDestinationCity(p, origin) ? first : rest).add(p);
    }
    return <SeedProfile>[...first, ...rest];
  }
}
