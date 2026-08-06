import '../../auth/domain/app_user.dart';
import '../../monetization/domain/boost.dart';
import '../../profile/domain/profile_state.dart';
import 'boost_ranker.dart';

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

  /// Empujón MÁXIMO (en puntos de afinidad) de un Boost pagado dentro de la
  /// curación. Equivale a ~2 intereses en común: ayuda a entrar en el corte de
  /// [curatedLimit], pero no adelanta a quien comparte intención de relación
  /// (5 puntos), que es la promesa de Slow Dating.
  ///
  /// DECISIÓN: antes, Slow Dating se aplicaba DESPUÉS de BoostAwareRanker y
  /// reordenaba/truncaba por su propio score, así que el bonus del Boost
  /// desaparecía por completo: para cualquiera con Slow Dating activo, un Boost
  /// pagado no daba ni un puesto de visibilidad extra (dinero cobrado sin
  /// servicio). En vez de desactivar Slow Dating (rompería lo que el usuario
  /// eligió) o de avisar al comprador (no puede saber cuántos receptores lo
  /// tienen activo), el Boost entra como bonus ACOTADO dentro de la propia
  /// curación: sigue habiendo curación, pero el Boost sí compra exposición.
  static const double maxBoostBonus = 3.0;

  static List<SeedProfile> curate({
    required List<SeedProfile> profiles,
    required AppUser? me,
    Map<String, ActiveBoost> activeBoosts = const <String, ActiveBoost>{},
    DateTime? now,
    int limit = curatedLimit,
  }) {
    if (profiles.length <= 1) return profiles;

    final String myIntent = (me?.relationshipIntent ?? '').trim().toLowerCase();
    final Set<String> myInterests = <String>{
      for (final String i in me?.interests ?? const <String>[])
        i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);

    final DateTime at = now ?? DateTime.now();
    // `order` conserva la posición de entrada: la lista ya llega ordenada por
    // el ranking orgánico y `sort` de Dart no es estable, así que sin este
    // desempate los empates se barajaban y el orden previo se perdía.
    final List<({SeedProfile profile, double score, int order})> scored = <({
      SeedProfile profile,
      double score,
      int order
    })>[
      for (int i = 0; i < profiles.length; i++)
        (
          profile: profiles[i],
          score: _score(profiles[i], myIntent, myInterests) +
              _boostBonus(activeBoosts[profiles[i].id], at),
          order: i,
        ),
    ]..sort((({SeedProfile profile, double score, int order}) a,
          ({SeedProfile profile, double score, int order}) b) {
        final int byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.order.compareTo(b.order);
      });

    return scored
        .take(limit)
        .map((({SeedProfile profile, double score, int order}) e) => e.profile)
        .toList(growable: false);
  }

  /// Empujón por Boost pagado, proporcional al `priorityBonus` real y acotado
  /// a [maxBoostBonus]. Reusa la escala de [BoostAwareRanker] para que boost
  /// normal y superboost mantengan la misma proporción entre sí.
  static double _boostBonus(ActiveBoost? boost, DateTime at) {
    final double organicShare =
        BoostAwareRanker.boostContribution(boost, at: at);
    if (organicShare <= 0) return 0;
    return (organicShare / BoostAwareRanker.maxBoostScore) * maxBoostBonus;
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
