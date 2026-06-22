import 'dart:math' as math;

import '../../profile/domain/profile_state.dart';
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
    int? defaultMaxKm,
  }) {
    return profiles.where((SeedProfile p) {
      if (p.id == myUid) return false;
      if (excludedUids.contains(p.id)) return false;

      // --- RELEVANCIA GEOGRÁFICA (siempre, salvo modo viajes que pasa
      //     myLat/myLng = null y myCountry = destino). ---
      // 1) Si hay coordenadas en ambos lados: distancia real con el radio del
      //    usuario (o el por defecto).
      // 2) Si faltan coordenadas (perfiles sin geo): fallback por país.
      // 3) Si no se puede determinar nada, no se excluye (permisivo).
      final int maxKm =
          filters.maxDistanceKm ?? defaultMaxKm ?? defaultRadiusKm;
      final bool haveBothCoords =
          myLat != null && myLng != null && p.lat != null && p.lng != null;
      if (haveBothCoords) {
        if (_distanceKm(myLat, myLng, p.lat!, p.lng!) > maxKm) return false;
      } else {
        final String mine = _canonCountry(myCountry);
        final String theirs = _canonCountry(p.country);
        if (mine.isNotEmpty && theirs.isNotEmpty && mine != theirs) {
          return false;
        }
      }

      final bool iWantThem = myInterestedIn.isEmpty ||
          p.gender.isEmpty ||
          myInterestedIn.contains(p.gender);
      final bool theyWantMe = p.interestedIn.isEmpty ||
          myGender.isEmpty ||
          p.interestedIn.contains(myGender);
      if (!iWantThem || !theyWantMe) return false;

      // --- Siempre duros ---
      if (filters.showGenders.isNotEmpty &&
          p.gender.isNotEmpty &&
          !filters.showGenders.contains(p.gender)) {
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
      if (_excludesString(filters, FeedFilters.kGoal,
          filters.relationshipGoal, p.relationshipGoal)) {
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
          (p.heightCm! < filters.minHeight || p.heightCm! > filters.maxHeight)) {
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

  /// Normaliza el nombre de país a un token canónico para comparar pese a
  /// idioma (los mocks usan español "España"; el picker usa inglés "Spain").
  /// Países desconocidos: se compara su nombre en minúsculas tal cual.
  static String _canonCountry(String raw) {
    final String s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    const Map<String, String> aliases = <String, String>{
      'españa': 'es', 'espana': 'es', 'spain': 'es',
      'italia': 'it', 'italy': 'it',
      'francia': 'fr', 'france': 'fr',
      'portugal': 'pt',
      'alemania': 'de', 'germany': 'de', 'deutschland': 'de',
      'reino unido': 'gb', 'united kingdom': 'gb', 'inglaterra': 'gb',
      'estados unidos': 'us', 'united states': 'us', 'usa': 'us',
      'méxico': 'mx', 'mexico': 'mx',
      'argentina': 'ar', 'brasil': 'br', 'brazil': 'br',
      'países bajos': 'nl', 'paises bajos': 'nl', 'netherlands': 'nl',
      'bélgica': 'be', 'belgica': 'be', 'belgium': 'be',
      'irlanda': 'ie', 'ireland': 'ie',
    };
    return aliases[s] ?? s;
  }

  /// Distancia haversine en km.
  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
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
