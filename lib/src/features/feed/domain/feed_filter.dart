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

  static List<SeedProfile> apply({
    required List<SeedProfile> profiles,
    required String myUid,
    required String myGender,
    required List<String> myInterestedIn,
    required Set<String> excludedUids,
    FeedFilters filters = const FeedFilters(),
    double? myLat,
    double? myLng,
  }) {
    return profiles.where((SeedProfile p) {
      if (p.id == myUid) return false;
      if (excludedUids.contains(p.id)) return false;

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
      // Distancia.
      final int? maxKm = filters.maxDistanceKm;
      if (filters.isDealbreaker(FeedFilters.kDistance) &&
          maxKm != null &&
          myLat != null &&
          myLng != null &&
          p.lat != null &&
          p.lng != null) {
        if (_distanceKm(myLat, myLng, p.lat!, p.lng!) > maxKm) return false;
      }
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
