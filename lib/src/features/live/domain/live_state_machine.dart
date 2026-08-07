/// Máquina de estados del feed en vivo: transiciones VÁLIDAS y solo esas.
///
/// PORQUÉ una máquina explícita: el vivo es tiempo real con dos clientes
/// escribiendo a la vez y un backend que también cierra sesiones. Sin una
/// tabla de transiciones, un snapshot que llega tarde (o un cliente
/// modificado) puede "revivir" una sesión ya cerrada y reabrir la cámara
/// frente a alguien que ya salió, denunció o fue sancionado. Aquí eso es
/// imposible por construcción: `ended` no tiene salidas.
library;

import 'live_constants.dart';
import 'live_session.dart';

/// Tabla de transiciones permitidas: `ringing -> active -> ended`.
///
/// Nótese que NO hay auto-transiciones (`active -> active`): un estado no
/// cambia a sí mismo, y aceptarlas escondería reescrituras idempotentes que
/// preferimos ver como "no hay transición".
const Map<LiveSessionStatus, Set<LiveSessionStatus>> kLiveTransitions =
    <LiveSessionStatus, Set<LiveSessionStatus>>{
  // Suena: o conectan, o se cae (nadie descuelga, uno sale, moderación).
  LiveSessionStatus.ringing: <LiveSessionStatus>{
    LiveSessionStatus.active,
    LiveSessionStatus.ended,
  },
  // En vídeo: la única salida es terminar.
  LiveSessionStatus.active: <LiveSessionStatus>{
    LiveSessionStatus.ended,
  },
  // Terminada: IRREVERSIBLE. Nada puede revivir una sesión terminada.
  LiveSessionStatus.ended: <LiveSessionStatus>{},
};

/// ¿Es válido pasar de [from] a [to]? Función PURA, sin estado ni reloj.
bool canTransition(LiveSessionStatus from, LiveSessionStatus to) {
  return kLiveTransitions[from]?.contains(to) ?? false;
}

/// Aplica una transición: devuelve el nuevo estado o null si es inválida.
///
/// Devolver null (en vez de lanzar) permite que la capa de datos ignore
/// snapshots desordenados sin romper la pantalla.
LiveSessionStatus? nextStatus(LiveSessionStatus from, LiveSessionStatus to) {
  return canTransition(from, to) ? to : null;
}

/// Resultado del cruce de veredictos de los dos participantes.
enum LiveMatchOutcome {
  /// Falta al menos un veredicto: no se decide nada todavía.
  pending,

  /// Ambos deslizaron a la derecha -> match + chat (writeMatchAndChat).
  matched,

  /// Al menos uno pasó -> no hay match; el `pass` escribe dislike.
  noMatch;

  bool get isPending => this == LiveMatchOutcome.pending;
  bool get isMatch => this == LiveMatchOutcome.matched;
}

/// Cruce de veredictos ya resuelto, con lo que hay que hacer después.
class LiveVerdictResolution {
  const LiveVerdictResolution({
    required this.outcome,
    required this.dislikedBy,
    this.endReason,
  });

  final LiveMatchOutcome outcome;

  /// Quiénes deslizaron a la izquierda: por cada uno hay que escribir un
  /// dislike (`col.dislikes`, directedId) para no volver a emparejarlos en el
  /// feed normal. Se rellena aunque el otro aún no haya decidido.
  final List<String> dislikedBy;

  /// Motivo de cierre asociado, si el cruce ya cierra la sesión.
  final LiveEndReason? endReason;

  bool get isMatch => outcome.isMatch;
  bool get isPending => outcome.isPending;
}

/// Decide el resultado a partir de los veredictos de ambos.
///
/// Reglas (las MISMAS que el resto de la app, no inventamos otras):
/// - like + like -> match; el backend usa `writeMatchAndChat`.
/// - cualquier pass -> no match, y quien pasó escribe dislike.
/// - falta alguno -> pendiente (esperamos; el otro puede tardar).
///
/// Un `pass` ya conocido se registra como dislike aunque el cruce siga
/// pendiente: si el usuario cierra la app, su decisión no debe perderse.
LiveVerdictResolution resolveVerdicts({
  required String uidA,
  required String uidB,
  LiveVerdict? verdictA,
  LiveVerdict? verdictB,
}) {
  final List<String> disliked = <String>[
    if (verdictA == LiveVerdict.pass) uidA,
    if (verdictB == LiveVerdict.pass) uidB,
  ];

  if (verdictA == null || verdictB == null) {
    return LiveVerdictResolution(
      outcome: LiveMatchOutcome.pending,
      dislikedBy: List<String>.unmodifiable(disliked),
    );
  }

  if (verdictA.isLike && verdictB.isLike) {
    return const LiveVerdictResolution(
      outcome: LiveMatchOutcome.matched,
      dislikedBy: <String>[],
      endReason: LiveEndReason.matched,
    );
  }

  return LiveVerdictResolution(
    outcome: LiveMatchOutcome.noMatch,
    dislikedBy: List<String>.unmodifiable(disliked),
    endReason: LiveEndReason.left,
  );
}

/// Igual que [resolveVerdicts] pero tomando los uids de la propia sesión.
LiveVerdictResolution resolveSessionVerdicts(
  LiveSession session, {
  LiveVerdict? verdictA,
  LiveVerdict? verdictB,
}) {
  return resolveVerdicts(
    uidA: session.userA,
    uidB: session.userB,
    verdictA: verdictA,
    verdictB: verdictB,
  );
}

/// Cierre automático por tiempo: devuelve `timeout` cuando la sesión sigue
/// viva y ya pasó el tope de 3 minutos; null en cualquier otro caso.
///
/// Se separa del modelo para que quien orquesta (controlador) tenga UNA sola
/// pregunta que hacer en cada tick del timer.
LiveEndReason? expiryEndReason(LiveSession session, {DateTime? now}) {
  return session.shouldAutoEnd(now: now) ? LiveEndReason.timeout : null;
}

/// Intento de cierre de una sesión, resuelto en el dominio.
///
/// Devuelve la sesión ya cerrada, o null si la transición no es válida
/// (típicamente porque YA estaba cerrada: el primer cierre gana y el segundo
/// se ignora, que es lo que queremos con dos clientes compitiendo).
LiveSession? endSession(
  LiveSession session, {
  required LiveEndReason reason,
  String? endedBy,
  DateTime? now,
}) {
  if (!canTransition(session.status, LiveSessionStatus.ended)) return null;
  final DateTime at = now ?? DateTime.now();
  return session.copyWith(
    status: LiveSessionStatus.ended,
    endReason: reason,
    endedBy: endedBy,
    endedAt: at,
    updatedAt: at,
  );
}

/// Paso de `ringing` a `active` (ambos conectaron el vídeo).
///
/// Fija `startedAt` y `endsAt` para que el tope de 3 minutos exista desde el
/// primer segundo: una sesión activa sin vencimiento sería una llamada
/// infinita con un desconocido.
LiveSession? startSession(LiveSession session, {DateTime? now}) {
  if (!canTransition(session.status, LiveSessionStatus.active)) return null;
  final DateTime at = now ?? DateTime.now();
  return LiveSession(
    id: session.id,
    userA: session.userA,
    userB: session.userB,
    status: LiveSessionStatus.active,
    endReason: session.endReason,
    endedBy: session.endedBy,
    createdAt: session.createdAt,
    startedAt: session.startedAt ?? at,
    endsAt: session.endsAt ?? at.add(LiveConstants.sessionMax),
    endedAt: session.endedAt,
    updatedAt: at,
  );
}
