/// Attra Match Journey: estado de avance de un match (recorrido guiado para
/// reducir chats muertos). Es un READ-MODEL: se DERIVA de señales que ya
/// existen (nº de mensajes reales, juegos completados, propuestas de cita,
/// última actividad), así funciona HOY sin desplegar nada. El parser `fromMap`
/// permite, más adelante, leer un `journeyStatus` PERSISTIDO en el match sin
/// cambiar la UI (la persistencia se añadiría por Cloud Function).
///
/// NUNCA bloquea el chat normal: solo informa y sugiere el siguiente paso.
library;

enum MatchJourneyStatus {
  newMatch('new_match'),
  icebreakerSuggested('icebreaker_suggested'),
  icebreakerStarted('icebreaker_started'),
  gameStarted('game_started'),
  gameCompleted('game_completed'),
  conversationActive('conversation_active'),
  dateProposed('date_proposed'),
  dateAccepted('date_accepted'),
  dateCompleted('date_completed'),
  archived('archived');

  const MatchJourneyStatus(this.wireName);
  final String wireName;

  bool get isTerminal =>
      this == MatchJourneyStatus.dateCompleted ||
      this == MatchJourneyStatus.archived;

  static MatchJourneyStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final MatchJourneyStatus s in MatchJourneyStatus.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return MatchJourneyStatus.newMatch;
  }
}

/// CTA contextual sugerida en el chat (Fase 8). La UI decide cómo pintarla.
enum MatchJourneyCta {
  launchIcebreaker,
  playQuickGame,
  proposePlan,
  reactivate,
  none,
}

class MatchJourney {
  const MatchJourney({
    required this.status,
    this.coolingDown = false,
  });

  final MatchJourneyStatus status;

  /// El match se está "enfriando" (Fase 9): sin actividad reciente y sin avance.
  final bool coolingDown;

  /// Umbral de mensajes "reales" para considerar la conversación activa.
  static const int conversationThreshold = 6;

  /// Tiempo sin actividad tras el cual un match no-terminal se enfría.
  static const Duration coolingAfter = Duration(hours: 48);

  /// Estado PERSISTIDO si existe (`matches/{id}.journeyStatus`); si no, cae al
  /// [fallback] derivado. Pensado para matches antiguos sin journey.
  factory MatchJourney.fromMap(
    Map<String, dynamic>? map, {
    required MatchJourneyStatus fallback,
    bool coolingDown = false,
  }) {
    final Object? raw = map?['journeyStatus'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return MatchJourney(status: fallback, coolingDown: coolingDown);
    }
    return MatchJourney(
      status: MatchJourneyStatus.fromValue(raw),
      coolingDown: coolingDown,
    );
  }

  /// Deriva el estado a partir de señales que la app ya tiene. PURO/testeable.
  ///
  /// Prioridad (de más avanzado a menos): cita aceptada > cita propuesta >
  /// conversación activa > juego completado > juego empezado > icebreaker >
  /// match nuevo.
  static MatchJourney derive({
    required int realMessageCount,
    bool hasStartedGame = false,
    bool hasCompletedGame = false,
    bool icebreakerUsed = false,
    String? dateProposalStatus, // pending | accepted | declined | countered
    bool dateCompleted = false,
    DateTime? lastActivityAt,
    DateTime? now,
  }) {
    final MatchJourneyStatus status = _deriveStatus(
      realMessageCount: realMessageCount,
      hasStartedGame: hasStartedGame,
      hasCompletedGame: hasCompletedGame,
      icebreakerUsed: icebreakerUsed,
      dateProposalStatus: dateProposalStatus,
      dateCompleted: dateCompleted,
    );
    return MatchJourney(
      status: status,
      coolingDown: _isCooling(status, lastActivityAt, now ?? DateTime.now()),
    );
  }

  static MatchJourneyStatus _deriveStatus({
    required int realMessageCount,
    required bool hasStartedGame,
    required bool hasCompletedGame,
    required bool icebreakerUsed,
    required String? dateProposalStatus,
    required bool dateCompleted,
  }) {
    final String prop = (dateProposalStatus ?? '').trim().toLowerCase();
    if (dateCompleted) return MatchJourneyStatus.dateCompleted;
    if (prop == 'accepted') return MatchJourneyStatus.dateAccepted;
    if (prop == 'pending' || prop == 'countered') {
      return MatchJourneyStatus.dateProposed;
    }
    if (realMessageCount >= conversationThreshold) {
      return MatchJourneyStatus.conversationActive;
    }
    if (hasCompletedGame) return MatchJourneyStatus.gameCompleted;
    if (hasStartedGame) return MatchJourneyStatus.gameStarted;
    if (icebreakerUsed) return MatchJourneyStatus.icebreakerStarted;
    if (realMessageCount == 0) return MatchJourneyStatus.newMatch;
    // 1-5 mensajes, sin juego ni icebreaker: aún rompiendo el hielo.
    return MatchJourneyStatus.icebreakerSuggested;
  }

  static bool _isCooling(
      MatchJourneyStatus status, DateTime? lastActivityAt, DateTime now) {
    if (status.isTerminal ||
        status == MatchJourneyStatus.dateProposed ||
        status == MatchJourneyStatus.dateAccepted) {
      return false;
    }
    if (lastActivityAt == null) return false;
    return now.difference(lastActivityAt) >= coolingAfter;
  }

  /// CTA contextual a mostrar en el chat (Fase 8). Simple y no intrusiva.
  MatchJourneyCta get suggestedCta {
    if (coolingDown) return MatchJourneyCta.reactivate;
    switch (status) {
      case MatchJourneyStatus.newMatch:
      case MatchJourneyStatus.icebreakerSuggested:
        return MatchJourneyCta.launchIcebreaker;
      case MatchJourneyStatus.icebreakerStarted:
      case MatchJourneyStatus.gameStarted:
        return MatchJourneyCta.playQuickGame;
      case MatchJourneyStatus.gameCompleted:
      case MatchJourneyStatus.conversationActive:
        return MatchJourneyCta.proposePlan;
      case MatchJourneyStatus.dateProposed:
      case MatchJourneyStatus.dateAccepted:
      case MatchJourneyStatus.dateCompleted:
      case MatchJourneyStatus.archived:
        return MatchJourneyCta.none;
    }
  }

  /// Etiqueta humana y elegante del estado (Fase 8). Tono de producto, no infantil.
  String get label {
    if (coolingDown) return 'Enfriándose';
    switch (status) {
      case MatchJourneyStatus.newMatch:
        return 'Nuevo match';
      case MatchJourneyStatus.icebreakerSuggested:
      case MatchJourneyStatus.icebreakerStarted:
        return 'Rompiendo el hielo';
      case MatchJourneyStatus.gameStarted:
        return 'Juego activo';
      case MatchJourneyStatus.gameCompleted:
        return 'Buena sintonía';
      case MatchJourneyStatus.conversationActive:
        return 'Conversación activa';
      case MatchJourneyStatus.dateProposed:
        return 'Plan propuesto';
      case MatchJourneyStatus.dateAccepted:
        return 'Cita aceptada';
      case MatchJourneyStatus.dateCompleted:
        return 'Os habéis visto';
      case MatchJourneyStatus.archived:
        return 'Archivado';
    }
  }
}
