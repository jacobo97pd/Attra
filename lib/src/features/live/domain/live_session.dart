/// Modelo de dominio del feed en vivo. Dart PURO: ni una importación de
/// Firebase.
///
/// PORQUÉ puro: es la única forma de testear una función de tiempo real sin
/// red ni emulador. La capa de datos convierte snapshots a `Map` y llama a
/// [LiveSession.fromMap]; aquí solo hay reglas.
library;

import 'live_constants.dart';

/// Ciclo de vida de una sesión de vídeo 1:1.
///
/// `ringing` (sonando, aún no conectados) -> `active` (vídeo en curso) ->
/// `ended` (cerrada, IRREVERSIBLE).
enum LiveSessionStatus {
  ringing('ringing'),
  active('active'),
  ended('ended');

  const LiveSessionStatus(this.wireName);

  final String wireName;

  /// La sesión sigue en pie (hay o habrá vídeo).
  bool get isLive => this != LiveSessionStatus.ended;

  /// Estado final: nada puede sacarla de aquí.
  bool get isTerminal => this == LiveSessionStatus.ended;

  /// Tolerante con valores desconocidos, pero FAIL-CLOSED: si el backend
  /// escribe un estado que este cliente no entiende, damos la sesión por
  /// terminada. Nunca abrimos vídeo con un desconocido por un valor que no
  /// sabemos interpretar; como mucho el usuario ve una sesión cerrada de más.
  static LiveSessionStatus fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LiveSessionStatus s in LiveSessionStatus.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return LiveSessionStatus.ended;
  }
}

/// Motivo por el que se cerró la sesión (campo `endReason`).
enum LiveEndReason {
  /// Alguien salió/colgó.
  left('left'),

  /// Se agotó el tope de 3 minutos.
  timeout('timeout'),

  /// Alguien denunció al otro.
  reported('reported'),

  /// Corte inmediato por moderación (SafeSearch sobre el vídeo remoto).
  moderation('moderation'),

  /// Veredicto mutuo 'like': la sesión acaba porque hay match.
  matched('matched');

  const LiveEndReason(this.wireName);

  final String wireName;

  /// ¿El cierre fue por una sanción? La UI cambia el mensaje (y no ofrece
  /// "volver a buscar" inmediatamente).
  bool get isPunitive =>
      this == LiveEndReason.moderation || this == LiveEndReason.reported;

  /// Desconocido -> `left`, el motivo NEUTRO.
  ///
  /// PORQUÉ neutro y no `moderation`: el motivo se muestra al usuario y
  /// acusar a alguien de contenido inapropiado por no saber leer un string
  /// sería peor que no decir nada.
  static LiveEndReason fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LiveEndReason r in LiveEndReason.values) {
      if (r.wireName == raw || r.name == raw) return r;
    }
    return LiveEndReason.left;
  }

  /// Igual que [fromValue] pero devuelve null cuando NO hay motivo escrito
  /// (sesión aún viva). Distinguir "sin motivo" de "motivo raro" importa.
  static LiveEndReason? tryFromValue(Object? value) {
    final String raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return fromValue(raw);
  }
}

/// Decisión de un participante tras la videollamada.
enum LiveVerdict {
  /// Deslizó a la derecha: me interesa.
  like('like'),

  /// Deslizó a la izquierda: paso (escribe dislike para no repetir).
  pass('pass');

  const LiveVerdict(this.wireName);

  final String wireName;

  bool get isLike => this == LiveVerdict.like;

  /// Desconocido -> `pass`. FAIL-CLOSED: un valor que no entendemos JAMÁS
  /// puede acabar creando un match. Es preferible perder un match que
  /// fabricar uno que ninguno de los dos pidió.
  static LiveVerdict fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final LiveVerdict v in LiveVerdict.values) {
      if (v.wireName == raw || v.name == raw) return v;
    }
    return LiveVerdict.pass;
  }

  /// null cuando todavía no hay veredicto (el documento no existe o está
  /// vacío). El estado "pendiente" es distinto de "pass".
  static LiveVerdict? tryFromValue(Object? value) {
    final String raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return fromValue(raw);
  }
}

/// Documento `liveSessions/{sessionId}/verdicts/{uid}`.
class LiveVerdictEntry {
  const LiveVerdictEntry({
    required this.uid,
    required this.verdict,
    this.decidedAt,
  });

  final String uid;
  final LiveVerdict verdict;
  final DateTime? decidedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'verdict': verdict.wireName,
        if (decidedAt != null) 'decidedAt': decidedAt,
      };

  factory LiveVerdictEntry.fromMap(String uid, Map<String, dynamic> map) {
    return LiveVerdictEntry(
      uid: uid,
      verdict: LiveVerdict.fromValue(map['verdict']),
      decidedAt: liveDateFromValue(map['decidedAt']),
    );
  }
}

/// Documento `liveSessions/{sessionId}`.
///
/// El id es `pairId(uidA, uidB)` (ver `match/domain/pair_id.dart`): el mismo
/// truco de ids deterministas que el resto de match/chat, para que dos
/// clientes disparando a la vez no creen sesiones duplicadas.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.userA,
    required this.userB,
    required this.status,
    this.endReason,
    this.endedBy,
    this.createdAt,
    this.startedAt,
    this.endsAt,
    this.endedAt,
    this.updatedAt,
  });

  final String id;

  /// Participantes. `users` (array de 2) existe en el documento para poder
  /// consultar por `arrayContains` desde las reglas y las queries.
  final String userA;
  final String userB;

  final LiveSessionStatus status;
  final LiveEndReason? endReason;
  final String? endedBy;

  final DateTime? createdAt;

  /// Momento en que el vídeo pasó a `active`. Desde aquí cuentan los 3 min.
  final DateTime? startedAt;

  /// Vencimiento escrito por el backend (autoridad). Puede faltar mientras la
  /// sesión está `ringing`.
  final DateTime? endsAt;

  final DateTime? endedAt;
  final DateTime? updatedAt;

  List<String> get users => <String>[userA, userB];

  bool involves(String uid) => uid == userA || uid == userB;

  /// El otro participante. Devuelve [userA] cuando [uid] no es de la sesión,
  /// pero la UI debe filtrar antes con [involves].
  String otherUid(String uid) => uid == userB ? userA : userB;

  bool get isLive => status.isLive;
  bool get isEnded => status.isTerminal;

  /// Vencimiento efectivo.
  ///
  /// Preferimos el `endsAt` del servidor (autoridad, inmune al reloj del
  /// móvil); si aún no está escrito lo derivamos de `startedAt` + 3 min para
  /// que el cliente NUNCA se quede sin tope. Sin ninguno de los dos no hay
  /// caducidad calculable (sesión que todavía suena).
  DateTime? get effectiveEndsAt =>
      endsAt ?? startedAt?.add(LiveConstants.sessionMax);

  /// Tiempo que queda de sesión (nunca negativo). [Duration.zero] cuando ya
  /// venció; null si aún no hay reloj (sesión `ringing` sin `endsAt`).
  Duration? remaining({DateTime? now}) {
    final DateTime? deadline = effectiveEndsAt;
    if (deadline == null) return null;
    final Duration left = deadline.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// ¿Pasó ya el tope de 3 minutos? Compara contra [effectiveEndsAt].
  ///
  /// El instante exacto del vencimiento cuenta como caducada (`>=`): en el
  /// límite preferimos cortar, no estirar.
  bool isExpired({DateTime? now}) {
    final DateTime? deadline = effectiveEndsAt;
    if (deadline == null) return false;
    return !(now ?? DateTime.now()).isBefore(deadline);
  }

  /// El cliente debe cerrar la sesión por su cuenta: sigue viva y ya venció.
  ///
  /// PORQUÉ también en el cliente si el backend ya la cierra: el scheduler
  /// puede tardar, y tres minutos es un contrato con el usuario. En cuanto
  /// vence, cortamos el vídeo local y pedimos veredicto.
  bool shouldAutoEnd({DateTime? now}) => isLive && isExpired(now: now);

  LiveSession copyWith({
    LiveSessionStatus? status,
    LiveEndReason? endReason,
    String? endedBy,
    DateTime? startedAt,
    DateTime? endsAt,
    DateTime? endedAt,
    DateTime? updatedAt,
  }) {
    return LiveSession(
      id: id,
      userA: userA,
      userB: userB,
      status: status ?? this.status,
      endReason: endReason ?? this.endReason,
      endedBy: endedBy ?? this.endedBy,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      endedAt: endedAt ?? this.endedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Payload de escritura. Las fechas van como [DateTime]: el SDK de
  /// Firestore las convierte, y así el dominio no depende de `Timestamp`.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'users': users,
        'userA': userA,
        'userB': userB,
        'status': status.wireName,
        if (endReason != null) 'endReason': endReason!.wireName,
        if (endedBy != null) 'endedBy': endedBy,
        if (createdAt != null) 'createdAt': createdAt,
        if (startedAt != null) 'startedAt': startedAt,
        if (endsAt != null) 'endsAt': endsAt,
        if (endedAt != null) 'endedAt': endedAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  /// Parseo tolerante: campos que faltan o vienen con tipos raros no revientan
  /// la pantalla; caen a un valor seguro (ver [LiveSessionStatus.fromValue]).
  factory LiveSession.fromMap(String id, Map<String, dynamic> map) {
    final List<String> users = _asStringList(map['users']);
    final String a = _asString(map['userA']) ??
        (users.isNotEmpty ? users.first : '');
    final String b = _asString(map['userB']) ??
        (users.length > 1 ? users[1] : '');

    return LiveSession(
      id: id,
      userA: a,
      userB: b,
      status: LiveSessionStatus.fromValue(map['status']),
      endReason: LiveEndReason.tryFromValue(map['endReason']),
      endedBy: _asString(map['endedBy']),
      createdAt: liveDateFromValue(map['createdAt']),
      startedAt: liveDateFromValue(map['startedAt']),
      endsAt: liveDateFromValue(map['endsAt']),
      endedAt: liveDateFromValue(map['endedAt']),
      updatedAt: liveDateFromValue(map['updatedAt']),
    );
  }
}

String? _asString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((Object? e) => (e ?? '').toString().trim())
      .where((String e) => e.isNotEmpty)
      .toList(growable: false);
}

/// Conversión tolerante a [DateTime] SIN importar `cloud_firestore`.
///
/// PORQUÉ pato (duck typing) en vez de `is Timestamp`: este paquete de dominio
/// no debe conocer Firebase para poder testearse en `dart test` puro, pero en
/// producción la capa de datos le pasa `Timestamp` tal cual. Probamos los
/// formatos conocidos y, como último recurso, llamamos a `toDate()`
/// dinámicamente; si el objeto no lo tiene, devolvemos null en vez de
/// propagar la excepción.
DateTime? liveDateFromValue(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true)
        .toLocal();
  }
  if (value is String) {
    final String raw = value.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
  if (value is Map) {
    // Forma serializada de un Timestamp (REST / JSON): {_seconds, _nanoseconds}.
    final Object? seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is num) {
      final Object? nanos = value['_nanoseconds'] ?? value['nanoseconds'];
      final int ms = (seconds * 1000).round() +
          (nanos is num ? (nanos / 1000000).round() : 0);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return null;
  }
  try {
    final dynamic candidate = value;
    final Object? converted = candidate.toDate();
    if (converted is DateTime) return converted;
  } catch (_) {
    // Objeto sin `toDate()`: no es una fecha, seguimos sin ella.
  }
  return null;
}
