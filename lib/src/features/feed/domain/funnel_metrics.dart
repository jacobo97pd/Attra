/// Cálculo PURO de las tasas de producto del embudo de Attra (Fase 13). Sin I/O
/// ni estado: recibe recuentos agregados y devuelve ratios [0..1]. La misma
/// fórmula la usa el job nocturno del backend (`productMetricsDaily`) y un
/// posible panel de admin. Testeable.
///
/// NUNCA se muestra como "nota" al usuario; son métricas de producto internas.
class FunnelCounts {
  const FunnelCounts({
    this.impressions = 0,
    this.profileOpens = 0,
    this.likes = 0,
    this.nopes = 0,
    this.attras = 0,
    this.matches = 0,
    this.conversationsStarted = 0,
    this.firstMessages = 0,
    this.replies = 0,
    this.gamesStarted = 0,
    this.gamesCompleted = 0,
    this.datesProposed = 0,
    this.datesAccepted = 0,
    this.newUsers = 0,
    this.newUsersWithMinExposure = 0,
  });

  final int impressions;
  final int profileOpens;
  final int likes;
  final int nopes;
  final int attras;
  final int matches;
  final int conversationsStarted;
  final int firstMessages;
  final int replies;
  final int gamesStarted;
  final int gamesCompleted;
  final int datesProposed;
  final int datesAccepted;
  final int newUsers;
  final int newUsersWithMinExposure;
}

/// Tasas derivadas [0..1].
class FunnelRates {
  const FunnelRates({
    required this.likeRate,
    required this.matchRate,
    required this.conversationStartRate,
    required this.replyRate,
    required this.gameCompletionRate,
    required this.dateProposalRate,
    required this.dateAcceptanceRate,
    required this.newUserMinExposureRate,
  });

  /// likes / (impresiones decididas = likes + nopes + attras).
  final double likeRate;

  /// matches / (likes + attras) — likes que cuajan.
  final double matchRate;

  /// conversaciones iniciadas / matches.
  final double conversationStartRate;

  /// respuestas / primeros mensajes (reciprocidad de chat).
  final double replyRate;

  /// juegos completados / iniciados.
  final double gameCompletionRate;

  /// citas propuestas / matches.
  final double dateProposalRate;

  /// citas aceptadas / propuestas.
  final double dateAcceptanceRate;

  /// % de usuarios nuevos que tuvieron exposición mínima (fairness/cold-start).
  final double newUserMinExposureRate;

  Map<String, double> toMap() => <String, double>{
        'likeRate': likeRate,
        'matchRate': matchRate,
        'conversationStartRate': conversationStartRate,
        'replyRate': replyRate,
        'gameCompletionRate': gameCompletionRate,
        'dateProposalRate': dateProposalRate,
        'dateAcceptanceRate': dateAcceptanceRate,
        'newUserMinExposureRate': newUserMinExposureRate,
      };
}

class FunnelMetrics {
  const FunnelMetrics._();

  static double _ratio(int num, int den) {
    if (den <= 0) return 0;
    final double r = num / den;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
  }

  static FunnelRates rates(FunnelCounts c) {
    final int decisions = c.likes + c.nopes + c.attras;
    return FunnelRates(
      likeRate: _ratio(c.likes + c.attras, decisions),
      matchRate: _ratio(c.matches, c.likes + c.attras),
      conversationStartRate: _ratio(c.conversationsStarted, c.matches),
      replyRate: _ratio(c.replies, c.firstMessages),
      gameCompletionRate: _ratio(c.gamesCompleted, c.gamesStarted),
      dateProposalRate: _ratio(c.datesProposed, c.matches),
      dateAcceptanceRate: _ratio(c.datesAccepted, c.datesProposed),
      newUserMinExposureRate:
          _ratio(c.newUsersWithMinExposure, c.newUsers),
    );
  }
}
