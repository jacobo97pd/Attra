import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_state.dart';

/// Slow Dating Mode (curación del feed, PURA y testeable).
///
/// Cuando el usuario activa Slow Dating, el feed deja de ser "deslizar masivo":
/// se REDUCE la exposición (se muestran menos perfiles por sesión) y se
/// PRIORIZAN las conexiones más afines e intencionales:
///   - mismo objetivo de relación (intención compartida) → fuerte
///   - intereses en común → medio
///   - perfiles más cuidados (bio + prompts) → ligero desempate
///
/// No bloquea ni excluye a nadie por sí mismo: solo reordena y limita. Si el
/// modo está desactivado no se llama a esta clase (el feed va como siempre).
class SlowDatingRanker {
  const SlowDatingRanker._();

  /// Máximo de perfiles mostrados por carga en modo Slow Dating (menos es más).
  static const int curatedLimit = 12;

  static List<SeedProfile> curate({
    required List<SeedProfile> profiles,
    required AppUser? me,
    int limit = curatedLimit,
  }) {
    if (profiles.length <= 1) return profiles;

    final String myIntent = (me?.relationshipIntent ?? '').trim().toLowerCase();
    final Set<String> myInterests = <String>{
      for (final String i in me?.interests ?? const <String>[])
        i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);

    final List<({SeedProfile profile, double score})> scored = profiles
        .map((SeedProfile p) => (
              profile: p,
              score: _score(p, myIntent, myInterests),
            ))
        .toList(growable: false)
      ..sort((({SeedProfile profile, double score}) a,
              ({SeedProfile profile, double score}) b) =>
          b.score.compareTo(a.score));

    return scored
        .take(limit)
        .map((({SeedProfile profile, double score}) e) => e.profile)
        .toList(growable: false);
  }

  /// Puntuación de afinidad/intencionalidad de un candidato respecto a mí.
  static double _score(
    SeedProfile p,
    String myIntent,
    Set<String> myInterests,
  ) {
    double s = 0;

    // Intención compartida (lo más importante en Slow Dating).
    final String theirIntent = p.relationshipGoal.trim().toLowerCase();
    if (myIntent.isNotEmpty &&
        theirIntent.isNotEmpty &&
        theirIntent == myIntent) {
      s += 5;
    }

    // Intereses en común.
    if (myInterests.isNotEmpty) {
      final int shared = p.interests
          .where((String i) => myInterests.contains(i.trim().toLowerCase()))
          .length;
      s += shared * 1.5;
    }

    // Perfiles más cuidados/intencionales (desempate ligero).
    if (p.bio.trim().length >= 40) s += 1;
    s += p.profilePrompts.length.clamp(0, 3) * 0.5;
    if (p.verified) s += 0.5;

    return s;
  }
}
