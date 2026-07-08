// Afinidad social — score PURO/testeable por intereses comunes. Se usa para
// ordenar personas (modo amigos) y grupos recomendados. Sin red ni IA (la IA
// futura puede afinar esto detrás de la misma forma; ver SocialAiRecommender).

class SocialAffinity {
  const SocialAffinity._();

  static String _norm(String s) => s.trim().toLowerCase();

  static Set<String> _normSet(Iterable<String> xs) =>
      xs.map(_norm).where((String s) => s.isNotEmpty).toSet();

  /// Intereses en común (normalizados) entre dos conjuntos.
  static Set<String> commonInterests(
      Iterable<String> a, Iterable<String> b) {
    return _normSet(a).intersection(_normSet(b));
  }

  /// Score [0..1] de afinidad por intereses (índice de Jaccard suavizado). 0 si
  /// alguno no tiene intereses. Recompensa el solapamiento sobre la unión, así
  /// que "3 de 4 comunes" puntúa más que "3 de 20".
  static double score(Iterable<String> a, Iterable<String> b) {
    final Set<String> sa = _normSet(a);
    final Set<String> sb = _normSet(b);
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    final int inter = sa.intersection(sb).length;
    if (inter == 0) return 0.0;
    final int union = sa.union(sb).length;
    return (inter / union).clamp(0.0, 1.0);
  }

  /// Igual que [score] pero en 0..100 (para mostrar como "%").
  static int scorePercent(Iterable<String> a, Iterable<String> b) =>
      (score(a, b) * 100).round();
}
