import '../../auth/domain/app_user.dart';
import '../../monetization/domain/boost.dart';
import '../../profile/domain/profile_state.dart';
import 'ranking.dart';

class BoostAwareRanker {
  const BoostAwareRanker._();

  /// Bonus máximo absoluto sobre el score orgánico. Mantiene el boost como
  /// acelerador de exposición, no como sustituto de compatibilidad.
  static const double maxBoostScore = 0.08;
  static const int maxPriorityBonus = 150;

  static List<SeedProfile> rank({
    required List<SeedProfile> profiles,
    required AppUser? me,
    required Map<String, ActiveBoost> activeBoosts,
  }) {
    if (profiles.length <= 1 || activeBoosts.isEmpty) {
      return RankingScorer.rank(profiles: profiles, me: me);
    }

    final List<_BoostedProfile> scored = RankingScorer.score(
      profiles: profiles,
      me: me,
    ).map((RankedProfile ranked) {
      final ActiveBoost? boost = activeBoosts[ranked.profile.id];
      final double bonus = boostContribution(boost);
      return _BoostedProfile(
        profile: ranked.profile,
        organicScore: ranked.score,
        boostBonus: bonus,
      );
    }).toList(growable: false);

    scored.sort((_BoostedProfile a, _BoostedProfile b) {
      final int total = b.totalScore.compareTo(a.totalScore);
      if (total != 0) return total;
      return b.organicScore.compareTo(a.organicScore);
    });

    // TODO(boost-blending): intercalar por cohortes/ciudad cuando haya volumen
    // real. Fase 4 aplica una bonificación controlada sin saltarse filtros.
    return scored
        .map((_BoostedProfile item) => item.profile)
        .toList(growable: false);
  }

  static double boostContribution(ActiveBoost? boost, {DateTime? at}) {
    if (boost == null || !boost.isActiveAt(at ?? DateTime.now())) return 0;
    final int cappedBonus =
        boost.priorityBonus.clamp(0, maxPriorityBonus).toInt();
    return (cappedBonus / maxPriorityBonus) * maxBoostScore;
  }
}

class _BoostedProfile {
  const _BoostedProfile({
    required this.profile,
    required this.organicScore,
    required this.boostBonus,
  });

  final SeedProfile profile;
  final double organicScore;
  final double boostBonus;

  double get totalScore => (organicScore + boostBonus).clamp(0.0, 1.0);
}
