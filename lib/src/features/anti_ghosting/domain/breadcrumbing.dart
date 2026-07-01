/// Anti-breadcrumbing (Attra Clear §9): detecta conversaciones "tibias" que no
/// avanzan. Lógica pura y testeable. No bloquea: solo orienta (nudge/cerrar).
bool isStalled({
  required DateTime? createdAt,
  required int realMessageCount,
  required bool hasDateProposal,
  required bool isClosed,
  DateTime? now,
}) {
  if (isClosed || hasDateProposal) return false;
  if (createdAt == null) return false;
  final DateTime ref = now ?? DateTime.now();
  final Duration age = ref.difference(createdAt);
  // Más de 7 días, con poca actividad y sin plan ni cierre => estancada.
  return age.inDays >= 7 && realMessageCount < 10;
}
