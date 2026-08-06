import '../../profile/domain/profile_state.dart';

/// Prioridad de "te ha dado like" (Plus/Pro) DENTRO de un orden ya calculado.
///
/// Antes esto se resolvía siempre con una partición (todos los que te habían
/// dado like al frente, el resto detrás) aplicada al final del pipeline. Con
/// una búsqueda IA activa eso destruía el orden por encaje: el feed decía
/// estar ordenado por parecido/descripción y en realidad lo estaba por "quién
/// me dio like". Con [apply] la señal puede aplicarse como un EMPUJÓN acotado
/// de posiciones (respeta el orden por encaje) o como partición completa
/// (cuando el orden es el orgánico y "al frente" es justo lo prometido).
class LikedMeRanker {
  const LikedMeRanker._();

  /// Posiciones que adelanta un perfil que te ha dado like cuando el orden
  /// previo tiene significado propio (ranking IA). Suficiente para que se vea
  /// pronto sin fingir un encaje que no tiene.
  static const int defaultNudge = 5;

  /// Devuelve [profiles] con los de [likedMeUids] adelantados.
  ///
  /// [nudgePositions] null => partición completa (comportamiento clásico).
  /// [nudgePositions] > 0 => cada uno adelanta como mucho esas posiciones,
  /// conservando el orden relativo del resto.
  static List<SeedProfile> apply({
    required List<SeedProfile> profiles,
    required Set<String> likedMeUids,
    int? nudgePositions,
  }) {
    if (profiles.length <= 1 || likedMeUids.isEmpty) return profiles;

    if (nudgePositions == null) {
      final List<SeedProfile> liked = <SeedProfile>[];
      final List<SeedProfile> rest = <SeedProfile>[];
      for (final SeedProfile p in profiles) {
        (likedMeUids.contains(p.id) ? liked : rest).add(p);
      }
      return <SeedProfile>[...liked, ...rest];
    }

    final int nudge = nudgePositions < 0 ? 0 : nudgePositions;
    final List<({SeedProfile profile, int key, int order})> scored = <({
      SeedProfile profile,
      int key,
      int order
    })>[
      for (int i = 0; i < profiles.length; i++)
        (
          profile: profiles[i],
          key: likedMeUids.contains(profiles[i].id) ? i - nudge : i,
          order: i,
        ),
    ]..sort((({SeedProfile profile, int key, int order}) a,
          ({SeedProfile profile, int key, int order}) b) {
        final int byKey = a.key.compareTo(b.key);
        if (byKey != 0) return byKey;
        // Empate (un like adelantado alcanza al que ya estaba ahí): manda el
        // orden por encaje, no el like.
        return a.order.compareTo(b.order);
      });

    return scored
        .map((({SeedProfile profile, int key, int order}) e) => e.profile)
        .toList(growable: false);
  }
}
