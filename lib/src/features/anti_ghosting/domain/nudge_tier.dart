/// Nivel de "nudge" dentro de un chat según cuánto lleva esperando tu respuesta
/// (Attra Clear §5). Lógica pura y testeable.
enum NudgeTier {
  none,

  /// ≥18 h: recordatorio suave ("¿Quieres seguir esta conversación?").
  gentle,

  /// ≥48 h: recordatorio más firme.
  firm,

  /// ≥96 h: la conversación parece enfriada (sugerir cerrar/archivar).
  cold;

  bool get isActive => this != NudgeTier.none;
}

/// Umbrales (horas). Fijos por diseño; si en el futuro se quieren remotos, se
/// leen de Remote Config sin cambiar la firma.
const int kNudgeGentleHours = 18;
const int kNudgeFirmHours = 48;
const int kNudgeColdHours = 96;

/// Devuelve el [NudgeTier] para una espera de [hoursWaiting] horas. Solo aplica
/// cuando es TU turno (lo decide quien llama). Negativo o pequeño => none.
NudgeTier nudgeTierForHours(num hoursWaiting) {
  if (hoursWaiting >= kNudgeColdHours) return NudgeTier.cold;
  if (hoursWaiting >= kNudgeFirmHours) return NudgeTier.firm;
  if (hoursWaiting >= kNudgeGentleHours) return NudgeTier.gentle;
  return NudgeTier.none;
}

/// Atajo a partir de un [Duration].
NudgeTier nudgeTierForDuration(Duration waited) =>
    nudgeTierForHours(waited.inMinutes / 60.0);
