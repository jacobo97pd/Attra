import 'dart:math' as math;

import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_state.dart';

/// Desglose de la puntuación de un candidato (para depurar/explicar el ranking).
class RankingBreakdown {
  const RankingBreakdown({
    required this.intent,
    required this.interests,
    required this.proximity,
    required this.quality,
    required this.activity,
    required this.likelihood,
    required this.novelty,
    required this.penalty,
    required this.total,
  });

  final double intent;
  final double interests;
  final double proximity;
  final double quality;
  final double activity;
  final double likelihood;
  final double novelty;
  final double penalty;
  final double total;
}

/// Candidato con su puntuación orgánica.
class RankedProfile {
  const RankedProfile({required this.profile, required this.breakdown});
  final SeedProfile profile;
  final RankingBreakdown breakdown;
  double get score => breakdown.total;
}

/// Señales por candidato que NO viven en el perfil (actividad, calidad
/// pre-calculada, penalizaciones de moderación). Inyectables para que el backend
/// pueda alimentarlas más adelante sin tocar la fórmula. Todo opcional => si no
/// hay dato, se usa un valor neutro (no rompe nada).
class RankingSignals {
  const RankingSignals({
    this.lastActiveAt,
    this.qualityOverride,
    this.activityOverride,
    this.likelihoodOverride,
    this.penalty = 0,
  });

  final DateTime? lastActiveAt;
  final double? qualityOverride;
  final double? activityOverride;
  final double? likelihoodOverride;

  /// Penalización [0..1] por señales negativas (reportes, shadow-moderación,
  /// perfil incompleto). Resta al final. La calcula el backend; cliente=0.
  final double penalty;
}

/// Ranking ORGÁNICO del feed (puro y testeable). NO aplica filtros duros (eso
/// es de [FeedFilter], antes): aquí solo se ORDENA por compatibilidad real.
///
/// Fórmula (todos los componentes normalizados 0..1):
///   score = wIntent·intent + wInterests·interests + wProximity·proximity
///         + wQuality·quality + wActivity·activity + wLikelihood·likelihood
///         + wNovelty·novelty − wPenalty·penalty
///
/// Diseño: monetizable pero JUSTO. Los Boosts y likes prioritarios se aplican
/// FUERA de aquí (capa superior), nunca saltándose los filtros ni esta base.
class RankingScorer {
  const RankingScorer._();

  // Pesos (suman ~1 en la parte positiva). Tunables sin tocar la lógica.
  static const double wIntent = 0.20;
  static const double wInterests = 0.18;
  static const double wProximity = 0.16;
  static const double wQuality = 0.14;
  static const double wActivity = 0.12;
  static const double wLikelihood = 0.12;
  static const double wNovelty = 0.08;
  static const double wPenalty = 0.30;

  /// Distancia (km) a partir de la cual la cercanía aporta ~0.
  static const double maxDistanceKm = 100;

  /// Ordena [profiles] de mayor a menor afinidad para [me]. [signalsFor] permite
  /// inyectar actividad/calidad/penalización por uid (todo opcional).
  static List<SeedProfile> rank({
    required List<SeedProfile> profiles,
    required AppUser? me,
    RankingSignals Function(SeedProfile)? signalsFor,
    bool diversify = true,
  }) {
    if (profiles.length <= 1) return profiles;
    final List<RankedProfile> scored = score(
      profiles: profiles,
      me: me,
      signalsFor: signalsFor,
    );
    scored.sort((RankedProfile a, RankedProfile b) =>
        b.score.compareTo(a.score));
    final List<SeedProfile> ordered =
        scored.map((RankedProfile r) => r.profile).toList(growable: true);
    return diversify ? _diversify(ordered) : ordered;
  }

  /// Devuelve el desglose por candidato (sin ordenar) — útil para depurar.
  static List<RankedProfile> score({
    required List<SeedProfile> profiles,
    required AppUser? me,
    RankingSignals Function(SeedProfile)? signalsFor,
  }) {
    final String myIntent =
        (me?.relationshipIntent ?? '').trim().toLowerCase();
    final Set<String> myInterests = <String>{
      for (final String i in me?.interests ?? const <String>[])
        i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);
    final double? myLat = me?.latitude;
    final double? myLng = me?.longitude;
    final DateTime now = DateTime.now();

    return profiles.map((SeedProfile p) {
      final RankingSignals sig =
          signalsFor?.call(p) ?? const RankingSignals();

      final double intent = _intentScore(myIntent, p.relationshipGoal);
      final double interests = _interestsScore(myInterests, p.interests);
      final double proximity = _proximityScore(myLat, myLng, p.lat, p.lng);
      final double quality = sig.qualityOverride ?? _qualityScore(p);
      final double activity = sig.activityOverride ??
          _activityScore(sig.lastActiveAt, now);
      // Probabilidad de like mutuo (proxy sin histórico): calidad + intención.
      final double likelihood =
          sig.likelihoodOverride ?? (0.55 * quality + 0.45 * intent);
      final double novelty = _noveltyScore(sig.lastActiveAt, now);
      final double penalty = sig.penalty.clamp(0.0, 1.0);

      final double total = (wIntent * intent +
              wInterests * interests +
              wProximity * proximity +
              wQuality * quality +
              wActivity * activity +
              wLikelihood * likelihood +
              wNovelty * novelty -
              wPenalty * penalty)
          .clamp(0.0, 1.0);

      return RankedProfile(
        profile: p,
        breakdown: RankingBreakdown(
          intent: intent,
          interests: interests,
          proximity: proximity,
          quality: quality,
          activity: activity,
          likelihood: likelihood,
          novelty: novelty,
          penalty: penalty,
          total: total,
        ),
      );
    }).toList(growable: false);
  }

  // --- Componentes ---------------------------------------------------------

  /// Intención de relación compartida. Permisivo si falta el dato.
  static double _intentScore(String mine, String their) {
    final String t = their.trim().toLowerCase();
    if (mine.isEmpty || t.isEmpty) return 0.6; // sin dato => neutro-alto
    return mine == t ? 1.0 : 0.2;
  }

  /// Intereses en común (estilo Jaccard suavizado).
  static double _interestsScore(Set<String> mine, List<String> their) {
    if (mine.isEmpty || their.isEmpty) return 0.5;
    final Set<String> theirs = <String>{
      for (final String i in their) i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);
    if (theirs.isEmpty) return 0.5;
    final int shared = mine.intersection(theirs).length;
    if (shared == 0) return 0.25;
    final int union = mine.union(theirs).length;
    // Jaccard + bonus por nº absoluto de coincidencias (hasta 3).
    final double jaccard = shared / union;
    final double bonus = (shared.clamp(0, 3)) / 3 * 0.4;
    return (0.6 * jaccard + bonus).clamp(0.0, 1.0);
  }

  /// Cercanía: 1 cerca, ~0 a [maxDistanceKm]. Neutro si falta geo.
  static double _proximityScore(
      double? aLat, double? aLng, double? bLat, double? bLng) {
    if (aLat == null || aLng == null || bLat == null || bLng == null) {
      return 0.5;
    }
    final double km = _haversineKm(aLat, aLng, bLat, bLng);
    final double n = (km / maxDistanceKm).clamp(0.0, 1.0);
    // Caída suave (cuadrática) para premiar mucho lo muy cercano.
    return (1 - n) * (1 - n);
  }

  /// Calidad del perfil: fotos (hasta 4), bio, prompts, verificación.
  static double _qualityScore(SeedProfile p) {
    final int photos = p.photos.isNotEmpty
        ? p.photos.length
        : (p.photoUrl.isNotEmpty ? 1 : 0);
    final double photoScore = (photos.clamp(0, 4)) / 4 * 0.45;
    final double bioScore =
        (p.bio.trim().length.clamp(0, 120)) / 120 * 0.25;
    final double promptScore =
        (p.profilePrompts.length.clamp(0, 3)) / 3 * 0.20;
    final double verifiedScore = p.verified ? 0.10 : 0.0;
    return (photoScore + bioScore + promptScore + verifiedScore)
        .clamp(0.0, 1.0);
  }

  /// Actividad reciente a partir de lastActiveAt. Neutro (0.5) si no hay dato.
  static double _activityScore(DateTime? lastActiveAt, DateTime now) {
    if (lastActiveAt == null) return 0.5;
    final int hours = now.difference(lastActiveAt).inHours;
    if (hours <= 24) return 1.0;
    if (hours <= 72) return 0.8;
    if (hours <= 24 * 7) return 0.6;
    if (hours <= 24 * 30) return 0.35;
    return 0.15;
  }

  /// Novedad: ligera prima a perfiles muy recientes/activos. Neutro sin dato.
  static double _noveltyScore(DateTime? lastActiveAt, DateTime now) {
    if (lastActiveAt == null) return 0.5;
    final int hours = now.difference(lastActiveAt).inHours;
    return hours <= 48 ? 0.7 : 0.5;
  }

  /// Diversidad: evita 3+ del mismo lugar seguidos (intercala sin perder el
  /// orden de afinidad de forma agresiva). Estable y barato.
  static List<SeedProfile> _diversify(List<SeedProfile> ordered) {
    final List<SeedProfile> out = <SeedProfile>[];
    final List<SeedProfile> deferred = <SeedProfile>[];
    String lastCity = '';
    int run = 0;
    for (final SeedProfile p in ordered) {
      final String city = p.city.trim().toLowerCase();
      if (city.isNotEmpty && city == lastCity && run >= 2) {
        deferred.add(p); // mismo sitio 3 veces seguidas: lo aplazamos un poco
        continue;
      }
      out.add(p);
      if (city == lastCity) {
        run++;
      } else {
        lastCity = city;
        run = 1;
      }
    }
    out.addAll(deferred); // los aplazados, al final (no se pierden)
    return out;
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371;
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
