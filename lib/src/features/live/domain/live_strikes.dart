/// Política de sanciones del feed en vivo. Lógica PURA a partir del recuento.
///
/// PORQUÉ pura y aparte: el vídeo va peer-to-peer, el servidor NO lo ve nunca,
/// así que toda la moderación cuelga de un contador (`liveStrikes/{uid}.count`)
/// que alimenta el backend con lo que SafeSearch detecta en los fotogramas del
/// vídeo REMOTO. Que la escalera de sanciones sea una función determinista y
/// testeable es lo que impide que se aplique "a medias" en cliente y backend.
///
/// Escalera del contrato:
///   1 strike  -> aviso + corte de la sesión
///   2 strikes -> bloqueo del vivo 24 h
///   3 strikes -> bloqueo permanente + reporte automático a moderación
library;

import 'live_constants.dart';
import 'live_session.dart' show liveDateFromValue;

/// Qué toca hacer ante el recuento actual de strikes.
enum LiveStrikeAction {
  /// Sin sanción (0 strikes).
  none,

  /// Aviso al usuario y corte inmediato de la sesión en curso.
  warnAndEnd,

  /// Bloqueo temporal del vivo (24 h).
  temporaryBlock,

  /// Bloqueo permanente del vivo + reporte a la cola de moderación.
  permanentBlock;

  bool get isBlocking =>
      this == LiveStrikeAction.temporaryBlock ||
      this == LiveStrikeAction.permanentBlock;
}

/// Resultado de aplicar la política. Todo lo que la capa de datos necesita
/// escribir en `liveStrikes/{uid}` y lo que la UI necesita mostrar.
class LiveStrikeDecision {
  const LiveStrikeDecision({
    required this.action,
    required this.endSession,
    required this.permanentlyBlocked,
    required this.reportToModeration,
    this.blockedUntil,
  });

  final LiveStrikeAction action;

  /// El corte por moderación es INMEDIATO para ambos: desde el primer strike
  /// se termina la sesión, no solo se avisa.
  final bool endSession;

  /// Fin del bloqueo temporal (null si no hay bloqueo temporal).
  final DateTime? blockedUntil;

  final bool permanentlyBlocked;

  /// Al 3.er strike se reporta automáticamente a la MISMA cola que
  /// `reportUser` (functions/src/safety.ts). No duplicamos flujo de reportes.
  final bool reportToModeration;

  /// ¿Puede entrar a la cola del vivo? Cualquier bloqueo lo impide.
  bool get blocksLive => permanentlyBlocked || blockedUntil != null;

  /// Solo hay aviso que mostrar cuando no está bloqueado (el bloqueo tiene su
  /// propio mensaje).
  bool get isWarningOnly => action == LiveStrikeAction.warnAndEnd;
}

/// Política de sanciones: única fuente de verdad de la escalera.
class LiveStrikePolicy {
  const LiveStrikePolicy._();

  /// Evalúa el recuento TOTAL de strikes de un usuario en el instante [now].
  ///
  /// [count] es acumulado, no incremental: se pasa el valor ya sumado del
  /// documento. Valores negativos o cero se tratan igual (sin sanción), para
  /// que un dato corrupto nunca castigue a nadie.
  ///
  /// A partir de [LiveConstants.maxStrikes] (3) la sanción es permanente: no
  /// hay escalera más allá, y un 4.º o 5.º strike no "reinicia" nada.
  static LiveStrikeDecision evaluate(int count, DateTime now) {
    if (count <= 0) {
      return const LiveStrikeDecision(
        action: LiveStrikeAction.none,
        endSession: false,
        permanentlyBlocked: false,
        reportToModeration: false,
      );
    }

    if (count >= LiveConstants.maxStrikes) {
      // Permanente: sin `blockedUntil` a propósito. Una fecha de fin invitaría
      // a que un cliente esperase a que caducara; el bloqueo permanente se
      // levanta solo desde moderación.
      return const LiveStrikeDecision(
        action: LiveStrikeAction.permanentBlock,
        endSession: true,
        permanentlyBlocked: true,
        reportToModeration: true,
      );
    }

    if (count == 1) {
      return const LiveStrikeDecision(
        action: LiveStrikeAction.warnAndEnd,
        endSession: true,
        permanentlyBlocked: false,
        reportToModeration: false,
      );
    }

    // count == 2 (y cualquier valor intermedio si algún día sube maxStrikes).
    return LiveStrikeDecision(
      action: LiveStrikeAction.temporaryBlock,
      endSession: true,
      permanentlyBlocked: false,
      reportToModeration: false,
      blockedUntil: now.add(LiveConstants.strikeBlock),
    );
  }
}

/// Documento `liveStrikes/{uid}`.
///
/// La autoridad es el backend; el cliente lo lee para saber si puede entrar al
/// vivo y para mostrar el motivo. Comprobarlo en cliente es cortesía (mensaje
/// claro), NUNCA la defensa: el emparejamiento lo hace el servidor.
class LiveStrikes {
  const LiveStrikes({
    required this.uid,
    required this.count,
    this.reasons = const <String>[],
    this.lastAt,
    this.blockedUntil,
    this.permanentlyBlocked = false,
  });

  /// Estado limpio: sirve de valor por defecto cuando el documento no existe.
  const LiveStrikes.clean(this.uid)
      : count = 0,
        reasons = const <String>[],
        lastAt = null,
        blockedUntil = null,
        permanentlyBlocked = false;

  final String uid;
  final int count;
  final List<String> reasons;
  final DateTime? lastAt;
  final DateTime? blockedUntil;
  final bool permanentlyBlocked;

  /// ¿Está vetado del vivo AHORA?
  ///
  /// El bloqueo de 24 h CADUCA solo: si `blockedUntil` ya pasó, deja de
  /// bloquear aunque el contador siga a 2 (los strikes no se borran, la
  /// sanción sí vence). El instante exacto de vencimiento ya NO bloquea.
  bool isBlockedAt(DateTime now) {
    if (permanentlyBlocked) return true;
    final DateTime? until = blockedUntil;
    if (until == null) return false;
    return now.isBefore(until);
  }

  /// Tiempo que queda de bloqueo temporal ([Duration.zero] si ya caducó o si
  /// no hay bloqueo temporal). En el permanente no aplica: devuelve zero.
  Duration remainingBlock(DateTime now) {
    final DateTime? until = blockedUntil;
    if (until == null) return Duration.zero;
    final Duration left = until.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Sanción vigente derivada del recuento. Útil para el mensaje de la UI.
  LiveStrikeDecision decisionAt(DateTime now) =>
      LiveStrikePolicy.evaluate(count, now);

  LiveStrikes copyWith({
    int? count,
    List<String>? reasons,
    DateTime? lastAt,
    DateTime? blockedUntil,
    bool? permanentlyBlocked,
  }) {
    return LiveStrikes(
      uid: uid,
      count: count ?? this.count,
      reasons: reasons ?? this.reasons,
      lastAt: lastAt ?? this.lastAt,
      blockedUntil: blockedUntil ?? this.blockedUntil,
      permanentlyBlocked: permanentlyBlocked ?? this.permanentlyBlocked,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'count': count,
        'reasons': reasons,
        if (lastAt != null) 'lastAt': lastAt,
        'blockedUntil': blockedUntil,
        'permanentlyBlocked': permanentlyBlocked,
      };

  factory LiveStrikes.fromMap(String uid, Map<String, dynamic> map) {
    final Object? rawReasons = map['reasons'];
    return LiveStrikes(
      uid: uid,
      count: _asInt(map['count']),
      reasons: rawReasons is List
          ? rawReasons
              .map((Object? e) => (e ?? '').toString())
              .where((String e) => e.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      lastAt: liveDateFromValue(map['lastAt']),
      blockedUntil: liveDateFromValue(map['blockedUntil']),
      // Solo `true` bloquea: un valor raro NUNCA veta a nadie por accidente.
      permanentlyBlocked: map['permanentlyBlocked'] == true,
    );
  }
}

/// Recuento tolerante.
///
/// PORQUÉ no un `as num?`: un `count` corrupto (string, null, lo que sea) NO
/// puede tumbar la pantalla del vivo. Ante la duda, 0 = sin sanción; castigar
/// por un dato ilegible sería peor que no castigar, y el backend —que es la
/// autoridad— seguirá bloqueando de verdad si toca.
int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}
