import 'dart:math' as math;

import '../../geo/domain/place_names.dart';
import '../../profile/domain/gender_matching.dart';
import '../../profile/domain/profile_state.dart';
import '../../social/domain/intent_mode.dart';
import 'feed_filters.dart';

/// Filtrado puro del feed (sin estado ni I/O) para que sea testeable.
///
/// Orden:
/// 1. Exclusión: mi propio uid y los uids ya interaccionados/bloqueados.
/// 2. Compatibilidad BIDIRECCIONAL de género (siempre dura).
/// 3. Filtros del usuario ([filters]). Un filtro con valor solo EXCLUYE si es
///    "no negociable" (su clave está en filters.dealbreakers); si no, es
///    preferencia blanda y no excluye. El género a mostrar y "solo con foto"
///    son siempre duros. Si falta el dato del candidato, no excluye (permisivo).
class FeedFilter {
  const FeedFilter._();

  /// Radio por defecto (km) cuando el usuario no tiene preferencia explícita.
  static const int defaultRadiusKm = 100;

  static List<SeedProfile> apply({
    required List<SeedProfile> profiles,
    required String myUid,
    required String myGender,
    required List<String> myInterestedIn,
    required Set<String> excludedUids,
    FeedFilters filters = const FeedFilters(),
    double? myLat,
    double? myLng,
    String myCountry = '',
    String myCountryIso2 = '',
    int? defaultMaxKm,
    int? maxKmOverride,
    String noGeoCity = '',
    bool requireGeo = false,
    bool travelersNeedGeo = false,
    String myCity = '',
    IntentMode myIntent = IntentMode.dating,
  }) {
    final String noGeoCityKey =
        noGeoCity.trim().isEmpty ? '' : PlaceNames.canonCity(noGeoCity);
    final String myCityKey =
        myCity.trim().isEmpty ? '' : PlaceNames.canonCity(myCity);
    return profiles.where((SeedProfile p) {
      if (p.id == myUid) return false;
      if (excludedUids.contains(p.id)) return false;
      // Ficha "de viaje" cuyo viaje ya terminó: está publicada en un destino
      // donde esa persona ya no está. El barrido del backend la devolverá a su
      // sitio; hasta entonces no se enseña.
      if (p.travelExpired) return false;

      // --- MODO AMIGOS: compatibilidad de intención (siempre dura). Un perfil
      //     solo aparece si comparte canal (dating/friends) con mi modo. Datos
      //     antiguos = `dating` por defecto → sin cambios respecto a antes.
      if (!IntentCompatibility.showsInFeed(myIntent, p.intentMode)) {
        return false;
      }

      // --- RELEVANCIA GEOGRÁFICA (siempre; en modo viajes myLat/myLng son el
      //     centro del destino y myCountry/myCountryIso2 el país de destino). ---
      // A) PAÍS: NUNCA de otro país. Se aplica SIEMPRE que se conozcan ambos
      //    países, tengan o no coordenadas (un perfil de otro país aunque esté
      //    cerca queda fuera). Por ISO2 cuando los dos lo tienen: el nombre
      //    llega en el idioma de cada teléfono o del selector ('Espanya',
      //    'Spain', 'Grecia', 'Greece') y comparar nombres vaciaba feeds.
      if (myCountry.trim().isNotEmpty || myCountryIso2.trim().isNotEmpty) {
        final bool? same =
            sameCountry(myCountryIso2, myCountry, p.countryIso2, p.country);
        if (same == false) return false;
      }
      // B) RADIO: si hay coordenadas en ambos lados, respeta el radio elegido
      //    por el usuario (o el por defecto). Sin coordenadas no se puede medir
      //    distancia → se queda en la regla de país de arriba.
      final int maxKm = maxKmOverride ??
          filters.maxDistanceKm ??
          defaultMaxKm ??
          defaultRadiusKm;
      final bool theyHaveGeo = p.lat != null && p.lng != null;
      if (myLat != null && myLng != null && theyHaveGeo) {
        if (_distanceKm(myLat, myLng, p.lat!, p.lng!) > maxKm) return false;
      }
      // Sin coordenadas no se puede demostrar que esté cerca. Donde el feed
      // PROMETE cercanía (respaldo de país, "gente de alrededor") no entra.
      if (requireGeo && !theyHaveGeo) return false;
      // Modo viajes: sin coordenadas solo entra quien dice estar en la ciudad
      // de destino. Si no, alguien de Madrid sin ubicación (o un viajero de
      // versiones antiguas, que se publicaba sin `geo`) salía en el feed de
      // quien viaja a Cádiz, que es justo la queja.
      if (noGeoCityKey.isNotEmpty &&
          !theyHaveGeo &&
          PlaceNames.canonCity(p.city) != noGeoCityKey) {
        return false;
      }
      // Feed de casa ([travelersNeedGeo]): una ficha "de viaje" SIN
      // coordenadas (viaje guardado por una versión antigua de la app, viaje a
      // un país entero o a una ciudad que no se pudo situar) se saltaba el
      // radio y la veía TODO el país: quien vive en Madrid y viaja a Cádiz
      // seguía saliendo, "de viaje", a la gente de Madrid. Sin centro no hay
      // distancia que medir, así que solo entra para quien está en esa misma
      // ciudad ([myCity]; sin ciudad propia no se puede comprobar y no entra).
      // Las fichas normales sin coordenadas no cambian: siguen con la regla de
      // país, como siempre.
      if (travelersNeedGeo &&
          p.traveling &&
          !theyHaveGeo &&
          (myCityKey.isEmpty || PlaceNames.canonCity(p.city) != myCityKey)) {
        return false;
      }

      // Compatibilidad de género: SOLO aplica cuando el solape es de DATING
      // (para citas importa la preferencia de género). En una conexión de
      // AMISTAD el género es irrelevante, así que no se filtra por él.
      final bool datingOverlap =
          myIntent.channels.contains(SocialChannel.dating) &&
              p.intentMode.channels.contains(SocialChannel.dating);
      if (datingOverlap) {
        // GenderMatching, y no `contains` a pelo: "a quién buscas" solo tiene
        // tres casillas y el género tiene ocho identidades, así que comparar
        // los dos campos en crudo dejaba fuera del feed a las cinco que no son
        // una casilla exacta. Ver gender_matching.dart.
        final bool iWantThem = GenderMatching.wants(myInterestedIn, p.gender);
        final bool theyWantMe = GenderMatching.wants(p.interestedIn, myGender);
        if (!iWantThem || !theyWantMe) return false;
      }

      // --- Siempre duros ---
      // "Mostrarme" usa el MISMO criterio que la compatibilidad de arriba: sus
      // casillas son las tres de `interestedIn`, asi que comparando en crudo
      // marcar "Mujeres" borraba del feed a las mujeres trans. El panel de
      // filtros no puede deshacer lo que arregla GenderMatching.
      if (filters.showGenders.isNotEmpty &&
          p.gender.isNotEmpty &&
          !GenderMatching.wants(filters.showGenders, p.gender)) {
        return false;
      }
      if (filters.onlyWithPhoto &&
          p.primaryPhotoUrl.isEmpty &&
          p.photos.isEmpty) {
        return false;
      }

      // --- Con deal-breaker: solo excluyen si "no negociable" ---
      // Edad.
      if (filters.isDealbreaker(FeedFilters.kAge) &&
          p.age != null &&
          (p.age! < filters.minAge || p.age! > filters.maxAge)) {
        return false;
      }
      // (La distancia se aplica arriba, en RELEVANCIA GEOGRÁFICA.)
      // Qué busca.
      if (_excludesString(filters, FeedFilters.kGoal, filters.relationshipGoal,
          p.relationshipGoal)) {
        return false;
      }
      // Tabaco / alcohol / estudios.
      if (_excludesString(
          filters, FeedFilters.kSmoking, filters.smoking, p.smoking)) {
        return false;
      }
      if (_excludesString(
          filters, FeedFilters.kDrinking, filters.drinking, p.drinking)) {
        return false;
      }
      if (_excludesString(filters, FeedFilters.kEducation,
          filters.educationLevel, p.educationLevel)) {
        return false;
      }
      // Etnicidad / religión (sensibles, ya vienen solo si hubo consentimiento).
      if (_excludesString(
          filters, FeedFilters.kEthnicity, filters.ethnicity, p.ethnicity)) {
        return false;
      }
      if (_excludesString(
          filters, FeedFilters.kReligion, filters.religion, p.religion)) {
        return false;
      }
      // Altura.
      if (filters.isDealbreaker(FeedFilters.kHeight) &&
          filters.heightActive &&
          p.heightCm != null &&
          (p.heightCm! < filters.minHeight ||
              p.heightCm! > filters.maxHeight)) {
        return false;
      }
      // Verificación.
      if (filters.isDealbreaker(FeedFilters.kVerified) &&
          filters.verifiedOnly &&
          !p.verified) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// Excluye si: el filtro tiene valor, es no-negociable, el candidato tiene
  /// dato y no coincide.
  static bool _excludesString(
      FeedFilters filters, String key, String? want, String have) {
    if (want == null) return false;
    if (!filters.isDealbreaker(key)) return false;
    if (have.isEmpty) return false; // permisivo si falta el dato
    return have != want;
  }

  /// ¿Son el mismo país? `null` = no se sabe (falta el dato en algún lado) y
  /// entonces NO se excluye (permisivo, como el resto de reglas).
  ///
  /// Con ISO2 en los dos lados manda el código. Si falta en alguno (seeds y
  /// documentos anteriores al backfill), se compara lo que haya: código contra
  /// nombre canónico y nombre contra nombre, así que no se pierde nada de lo que
  /// ya casaba por nombre.
  static bool? sameCountry(
    String myIso2,
    String myName,
    String theirIso2,
    String theirName,
  ) {
    final String a = myIso2.trim().toUpperCase();
    final String b = theirIso2.trim().toUpperCase();
    if (a.isNotEmpty && b.isNotEmpty) return a == b;
    final Set<String> mine = <String>{
      if (a.isNotEmpty) a.toLowerCase(),
      canonCountry(myName),
    }..remove('');
    final Set<String> theirs = <String>{
      if (b.isNotEmpty) b.toLowerCase(),
      canonCountry(theirName),
    }..remove('');
    if (mine.isEmpty || theirs.isEmpty) return null;
    return mine.intersection(theirs).isNotEmpty;
  }

  /// Normaliza el nombre de país a un token canónico para comparar pese a
  /// idioma (los mocks usan español "España"; el picker usa inglés "Spain").
  /// Es el RESPALDO de [sameCountry] cuando falta el ISO2: el mapa completo de
  /// nombres vive en assets/geo/country_names.json, pero el filtro es síncrono
  /// y puro. Países desconocidos: se compara su nombre normalizado tal cual.
  static String canonCountry(String raw) {
    final String s = PlaceNames.normalize(raw);
    if (s.isEmpty) return '';
    const Map<String, String> aliases = <String, String>{
      'espana': 'es',
      'spain': 'es',
      // Lo que escribían geocodificadores en catalán, euskera, alemán,
      // francés, italiano y portugués antes de fijar el idioma.
      'espanya': 'es',
      'espainia': 'es',
      'spanien': 'es',
      'espagne': 'es',
      'spagna': 'es',
      'espanha': 'es',
      'italia': 'it',
      'italy': 'it',
      'francia': 'fr',
      'france': 'fr',
      'portugal': 'pt',
      'alemania': 'de',
      'germany': 'de',
      'deutschland': 'de',
      'reino unido': 'gb',
      'united kingdom': 'gb',
      'inglaterra': 'gb',
      'estados unidos': 'us',
      'united states': 'us',
      'usa': 'us',
      'mexico': 'mx',
      'argentina': 'ar',
      'brasil': 'br',
      'brazil': 'br',
      'paises bajos': 'nl',
      'netherlands': 'nl',
      'holanda': 'nl',
      'belgica': 'be',
      'belgium': 'be',
      'irlanda': 'ie',
      'ireland': 'ie',
      'grecia': 'gr',
      'greece': 'gr',
      'suiza': 'ch',
      'switzerland': 'ch',
      'schweiz': 'ch',
      'suisse': 'ch',
      'marruecos': 'ma',
      'morocco': 'ma',
      'japon': 'jp',
      'japan': 'jp',
      'peru': 'pe',
      'canada': 'ca',
      'colombia': 'co',
      'chile': 'cl',
      'austria': 'at',
      'osterreich': 'at',
    };
    return aliases[s] ?? s;
  }

  /// Distancia haversine en km.
  static double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371; // radio Tierra km
    final double dLat = _rad(lat2 - lat1);
    final double dLon = _rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
