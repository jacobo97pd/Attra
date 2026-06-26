import 'dart:math' as math;

import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_state.dart';
import 'ranking_config.dart';

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
    // 5 scores COMPUESTOS del modelo (privados, server-side conceptual).
    this.profileQuality = 0,
    this.reciprocity = 0,
    this.connection = 0,
    this.trustSafety = 0,
    this.freshness = 0,
  });

  // Componentes base (alimentan los compuestos).
  final double intent;
  final double interests;
  final double proximity;
  final double quality;
  final double activity;
  final double likelihood;
  final double novelty;
  final double penalty;
  final double total;

  // Scores compuestos [0..1].
  final double profileQuality;
  final double reciprocity;
  final double connection;
  final double trustSafety;
  final double freshness;

  /// SOLO PARA DEV/ADMIN: explicación legible del score (reason codes). Nunca se
  /// muestra al usuario final. La consume `explainForDebugOnly`.
  Map<String, double> toDebugMap() => <String, double>{
        'profileQuality': profileQuality,
        'reciprocity': reciprocity,
        'connection': connection,
        'trustSafety': trustSafety,
        'freshness': freshness,
        'penalty': penalty,
        'total': total,
      };
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
    // --- Señales server-side del nuevo modelo (todas opcionales => neutro) ---
    this.profileQualityOverride,
    this.reciprocityOverride,
    this.connectionScore,
    this.trustSafetyScore,
    this.newUserBoostUntil,
    this.exposureCount24h = 0,
    this.exposureCap = 0,
  });

  final DateTime? lastActiveAt;
  final double? qualityOverride;
  final double? activityOverride;
  final double? likelihoodOverride;

  /// Penalización [0..1] por señales negativas (reportes, shadow-moderación,
  /// perfil incompleto). Resta al final. La calcula el backend; cliente=0.
  final double penalty;

  /// profileQualityScore precalculado [0..1] (calidad/completitud, NO belleza).
  final double? profileQualityOverride;

  /// reciprocityScore precalculado [0..1] (prob. de like mutuo viewer↔candidate).
  final double? reciprocityOverride;

  /// connectionScore [0..1]: prob. de conversación real (replyRate,
  /// gameCompletionRate, dateProposalRate…). Neutro 0.5 si falta.
  final double? connectionScore;

  /// trustSafetyScore [0..1]: confiabilidad (verificación, reportes, bloqueos).
  /// Neutro 0.5 si falta. Penaliza fuerte solo con señales claras.
  final double? trustSafetyScore;

  /// Ventana de cold-start: si está en el futuro, el candidato es "nuevo" y
  /// recibe un boost temporal de exploración.
  final DateTime? newUserBoostUntil;

  /// Veces que el candidato ya se ha mostrado en 24h (para el exposure cap).
  final int exposureCount24h;

  /// Tope de exposición en 24h. 0 = sin tope. Por encima, freshness baja.
  final int exposureCap;
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
  /// inyectar señales del backend por uid (todo opcional). [config] hace los
  /// pesos/jitter remotamente configurables. [jitterSeed] fija la randomización
  /// (tests).
  static List<SeedProfile> rank({
    required List<SeedProfile> profiles,
    required AppUser? me,
    RankingSignals Function(SeedProfile)? signalsFor,
    RankingConfig config = const RankingConfig(),
    bool diversify = true,
    int? jitterSeed,
  }) {
    if (profiles.length <= 1) return profiles;
    final List<RankedProfile> scored = score(
      profiles: profiles,
      me: me,
      signalsFor: signalsFor,
      config: config,
    );
    // Randomización controlada: ±jitter estable por candidato (no rompe el
    // orden básico; solo desempata y evita un feed 100% determinista).
    final math.Random rnd = math.Random(jitterSeed ?? 1);
    double jittered(RankedProfile r) {
      if (config.jitter <= 0) return r.score;
      final double j = (rnd.nextDouble() * 2 - 1) * config.jitter;
      return (r.score + j).clamp(0.0, 1.0);
    }

    scored.sort((RankedProfile a, RankedProfile b) =>
        jittered(b).compareTo(jittered(a)));
    final List<SeedProfile> ordered =
        scored.map((RankedProfile r) => r.profile).toList(growable: true);
    return diversify ? _diversify(ordered) : ordered;
  }

  /// Desglose por candidato (sin ordenar). Calcula los 5 scores COMPUESTOS del
  /// modelo (profileQuality, reciprocity, connection, trustSafety, freshness) y
  /// el total con los pesos de [config]. Todo normalizado [0..1].
  static List<RankedProfile> score({
    required List<SeedProfile> profiles,
    required AppUser? me,
    RankingSignals Function(SeedProfile)? signalsFor,
    RankingConfig config = const RankingConfig(),
  }) {
    final String myIntent = (me?.relationshipIntent ?? '').trim().toLowerCase();
    final Set<String> myInterests = <String>{
      for (final String i in me?.interests ?? const <String>[])
        i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);
    final double? myLat = me?.latitude;
    final double? myLng = me?.longitude;
    final DateTime now = DateTime.now();
    // Normaliza pesos por si la config remota no suma exactamente 1.
    final double wSum =
        config.organicWeightSum <= 0 ? 1 : config.organicWeightSum;

    return profiles.map((SeedProfile p) {
      final RankingSignals sig = signalsFor?.call(p) ?? const RankingSignals();

      // Componentes base.
      final double intent = _intentScore(myIntent, p.relationshipGoal);
      final double interests = _interestsScore(myInterests, p.interests);
      final double proximity = _proximityScore(myLat, myLng, p.lat, p.lng);
      final double quality = sig.qualityOverride ?? _qualityScore(p);
      final double activity =
          sig.activityOverride ?? _activityScore(sig.lastActiveAt, now);
      final double likelihood =
          sig.likelihoodOverride ?? (0.55 * quality + 0.45 * intent);
      final double novelty = _noveltyScore(sig.lastActiveAt, now);
      final double penalty = sig.penalty.clamp(0.0, 1.0);

      // --- 5 SCORES COMPUESTOS ---
      // 1) profileQuality: completitud (no belleza).
      final double profileQuality =
          (sig.profileQualityOverride ?? quality).clamp(0.0, 1.0);
      // 2) reciprocity: prob. de like mutuo (intención + intereses + cercanía +
      //    likelihood). Override si el backend lo precalcula con histórico.
      final double reciprocity = (sig.reciprocityOverride ??
              (0.30 * intent +
                  0.30 * interests +
                  0.20 * proximity +
                  0.20 * likelihood))
          .clamp(0.0, 1.0);
      // 3) connection: prob. de conversación real. Neutro si no hay señal.
      final double connection = (sig.connectionScore ?? 0.5).clamp(0.0, 1.0);
      // 4) trustSafety: confiabilidad. Si no hay override, deriva de verificación
      //    y baja con la penalización del backend. Neutro-alto por defecto.
      final double trustSafety =
          (sig.trustSafetyScore ?? ((p.verified ? 0.75 : 0.6) - 0.4 * penalty))
              .clamp(0.0, 1.0);
      // 5) freshness/exploration: novedad + cold-start − exposure cap.
      final double freshness =
          _freshnessScore(novelty, sig, now, config).clamp(0.0, 1.0);

      final double organic = (config.wProfileQuality * profileQuality +
              config.wReciprocity * reciprocity +
              config.wConnection * connection +
              config.wTrustSafety * trustSafety +
              config.wFreshness * freshness) /
          wSum;
      final double total =
          (organic - config.penaltyWeight * penalty).clamp(0.0, 1.0);

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
          profileQuality: profileQuality,
          reciprocity: reciprocity,
          connection: connection,
          trustSafety: trustSafety,
          freshness: freshness,
        ),
      );
    }).toList(growable: false);
  }

  /// SOLO DEV/ADMIN: explicación legible del ranking de un candidato (reason
  /// codes + breakdown). NUNCA llamar en el cliente de producción / mostrar al
  /// usuario. Devuelve texto para logs.
  static String explainForDebugOnly(RankedProfile r) {
    final RankingBreakdown b = r.breakdown;
    final List<String> codes = <String>[];
    if (b.profileQuality >= 0.7) codes.add('QUALITY_HIGH');
    if (b.profileQuality < 0.4) codes.add('QUALITY_LOW');
    if (b.reciprocity >= 0.7) codes.add('RECIPROCITY_HIGH');
    if (b.connection >= 0.7) codes.add('CONNECTION_HIGH');
    if (b.trustSafety < 0.4) codes.add('TRUST_LOW');
    if (b.freshness >= 0.7) codes.add('FRESH_BOOST');
    if (b.penalty > 0) codes.add('PENALIZED');
    return '[rank ${r.profile.id}] total=${b.total.toStringAsFixed(3)} '
        '${b.toDebugMap().entries.map((MapEntry<String, double> e) => '${e.key}=${e.value.toStringAsFixed(2)}').join(' ')} '
        'codes=${codes.join(',')}';
  }

  /// Freshness/exploración: novedad base, + cold-start si está en ventana de
  /// usuario nuevo, − penalización si superó el exposure cap (anti monopolio).
  static double _freshnessScore(
      double novelty, RankingSignals sig, DateTime now, RankingConfig config) {
    double f = novelty;
    final DateTime? until = sig.newUserBoostUntil;
    if (until != null && until.isAfter(now)) {
      f += config.coldStartBoost; // boost temporal a usuarios nuevos
    }
    if (sig.exposureCap > 0 && sig.exposureCount24h >= sig.exposureCap) {
      f -= config.exposureCapPenalty; // ya se mostró mucho: baja exposición
    }
    return f.clamp(0.0, 1.0);
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
    final int photos =
        p.photos.isNotEmpty ? p.photos.length : (p.photoUrl.isNotEmpty ? 1 : 0);
    final double photoScore = (photos.clamp(0, 4)) / 4 * 0.45;
    final double bioScore = (p.bio.trim().length.clamp(0, 120)) / 120 * 0.25;
    final double promptScore = (p.profilePrompts.length.clamp(0, 3)) / 3 * 0.20;
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
