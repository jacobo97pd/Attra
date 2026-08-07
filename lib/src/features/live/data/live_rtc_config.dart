/// Configuración ICE del feed en vivo (servidores STUN/TURN).
///
/// El vídeo va PEER-TO-PEER: no pasa por ningún servidor nuestro. Para que dos
/// móviles detrás de sus routers se encuentren hace falta ICE:
///
/// - STUN (constante, gratis): el móvil pregunta "¿cuál es mi IP pública y qué
///   puerto me ha asignado el router?" y publica esa dirección en el SDP.
///   Resuelve la mayoría de los casos domésticos.
///
/// - TURN (relé, de pago por GB): cuando el NAT es SIMÉTRICO (redes móviles de
///   algunas operadoras, wifis corporativas, CGNAT) el puerto que ve el
///   servidor STUN NO es el que servirá para el otro peer, así que la conexión
///   directa FRACASA y los dos se quedan en "conectando" para siempre. La única
///   salida es un relé que reenvíe el medio.
///
/// DE DÓNDE SALEN LAS CREDENCIALES TURN
/// ---------------------------------------------------------------------------
/// Del backend, EFÍMERAS, vía la callable `getLiveTurnCredentials`
/// (functions/src/liveTurn.ts). Aquí ya NO hay `--dart-define` con usuario y
/// clave: una credencial estática compilada en el binario se extrae del IPA/APK
/// con herramientas triviales, y como el relé se paga por gigabyte, quien la
/// saque tiene un proxy gratis a nuestra costa. El secreto compartido vive solo
/// en las variables de entorno de Functions.
///
/// Si la callable falla o el relé todavía no está contratado, [LiveTurnCache]
/// devuelve `null` y [LiveIceConfig.build] monta la configuración SOLO con
/// STUN: el vivo sigue funcionando, con el porcentaje de llamadas que no
/// conectan que eso implica.
///
/// Activar TURN es rellenar `LIVE_TURN_SECRET` y `LIVE_TURN_URLS` en
/// `functions/.env` (el detalle del formato y qué proveedor encaja está en
/// functions/src/liveTurn.ts): no hay que tocar ni volver a publicar el
/// cliente, porque aquí ya no queda ninguna credencial compilada.
library;

import 'package:flutter/foundation.dart';

/// Credenciales TURN efímeras emitidas por el backend.
@immutable
class LiveTurnCredentials {
  const LiveTurnCredentials({
    required this.urls,
    required this.username,
    required this.credential,
    required this.expiresAt,
  });

  final List<String> urls;
  final String username;
  final String credential;

  /// Momento (reloj LOCAL) a partir del cual dejamos de reutilizarlas.
  final DateTime expiresAt;

  bool get isUsable =>
      urls.isNotEmpty && username.isNotEmpty && credential.isNotEmpty;

  bool isValidAt(DateTime now) => isUsable && now.isBefore(expiresAt);

  /// Margen con el que se descartan ANTES de su caducidad real.
  ///
  /// Quien valida la caducidad es el servidor TURN, con SU reloj. Un móvil
  /// atrasado creería que la credencial sigue viva cuando el relé ya la
  /// rechaza, y el síntoma sería otra vez una llamada que no conecta. El margen
  /// absorbe el desfase típico y además evita renovar en mitad de la llamada.
  static const Duration renewMargin = Duration(minutes: 5);

  /// Lee la respuesta de `getLiveTurnCredentials`.
  ///
  /// Devuelve `null` cuando el backend responde `configured:false` (todavía no
  /// hay relé) o cuando la respuesta viene incompleta: en los dos casos la
  /// única acción sensata es seguir con STUN.
  ///
  /// La caducidad se calcula sobre el reloj LOCAL a partir de `ttlSeconds` y no
  /// sobre el `expiresAtMs` del servidor: si el móvil va desfasado, un instante
  /// absoluto ajeno haría que la caché tirara credenciales recién emitidas (o
  /// las guardara horas de más). El desfase que importa —el de la validación en
  /// el relé— lo cubre [renewMargin].
  static LiveTurnCredentials? fromCallable(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    if (data['configured'] != true) return null;

    final Object? rawServers = data['iceServers'];
    if (rawServers is! List) return null;

    final List<String> urls = <String>[];
    String username = '';
    String credential = '';
    for (final Object? entry in rawServers) {
      if (entry is! Map) continue;
      final Object? rawUrls = entry['urls'];
      final List<String> entryUrls = rawUrls is List
          ? rawUrls
              .map((Object? e) => e?.toString().trim() ?? '')
              .where((String e) => e.isNotEmpty)
              .toList(growable: false)
          : <String>[
              if ((rawUrls?.toString().trim() ?? '').isNotEmpty)
                rawUrls!.toString().trim(),
            ];
      if (entryUrls.isEmpty) continue;
      urls.addAll(entryUrls);
      username = (entry['username'] as Object?)?.toString() ?? username;
      credential = (entry['credential'] as Object?)?.toString() ?? credential;
    }

    if (urls.isEmpty || username.isEmpty || credential.isEmpty) return null;

    final int ttlSeconds = _asInt(data['ttlSeconds']) ?? 0;
    if (ttlSeconds <= 0) return null;

    final DateTime base = now ?? DateTime.now();
    Duration life = Duration(seconds: ttlSeconds) - renewMargin;
    // Un TTL más corto que el margen no puede dejar la vida útil en negativo:
    // se usarían una vez y se volverían a pedir en cada llamada.
    if (life < const Duration(minutes: 1)) life = const Duration(minutes: 1);

    return LiveTurnCredentials(
      urls: List<String>.unmodifiable(urls),
      username: username,
      credential: credential,
      expiresAt: base.add(life),
    );
  }
}

/// Quien sabe pedir credenciales al backend (`LiveService.fetchTurnCredentials`).
typedef LiveTurnFetcher = Future<LiveTurnCredentials?> Function();

/// Caché de credenciales TURN.
///
/// PORQUÉ EXISTE: las credenciales duran horas y sirven para todas las llamadas
/// de ese rato. Pedirlas en cada intento de conexión (o peor, por candidato
/// ICE) añadiría una ida y vuelta a Cloud Functions justo en el momento más
/// sensible del establecimiento, en una sesión que dura 3 minutos.
///
/// Además dedupe las peticiones simultáneas y aplica un backoff cuando la
/// llamada falla o no hay relé configurado: sin él, cada sesión volvería a
/// pagar el arranque en frío de una función que va a responder lo mismo.
class LiveTurnCache {
  LiveTurnCache({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Instancia compartida por todas las sesiones del proceso.
  static final LiveTurnCache instance = LiveTurnCache();

  final DateTime Function() _clock;

  /// Cuánto se espera antes de volver a preguntar tras un fallo o un
  /// `configured:false`. Suficiente para no machacar la función y corto para
  /// que activar TURN en el backend se note sin reinstalar la app.
  static const Duration failureBackoff = Duration(minutes: 10);

  LiveTurnCredentials? _cached;
  Future<LiveTurnCredentials?>? _inFlight;
  DateTime? _retryNotBefore;
  bool _warned = false;

  /// ¿Tenemos ahora mismo un relé utilizable? Lo consulta la UI para explicar
  /// un fallo de conexión que si no parecería arbitrario.
  bool get hasRelay => _cached?.isValidAt(_clock()) ?? false;

  /// Credenciales vigentes, pidiéndolas si hace falta.
  ///
  /// NUNCA lanza: sin TURN se sigue con STUN, y una excepción aquí tumbaría el
  /// arranque de la llamada por un problema que solo la degrada.
  Future<LiveTurnCredentials?> obtain(LiveTurnFetcher fetch) async {
    final DateTime now = _clock();

    final LiveTurnCredentials? cached = _cached;
    if (cached != null && cached.isValidAt(now)) return cached;
    _cached = null;

    final DateTime? retryAt = _retryNotBefore;
    if (retryAt != null && now.isBefore(retryAt)) return null;

    // Dedupe: la pantalla puede reintentar la conexión mientras la primera
    // petición sigue en vuelo.
    final Future<LiveTurnCredentials?>? pending = _inFlight;
    if (pending != null) return pending;

    final Future<LiveTurnCredentials?> request = _request(fetch);
    _inFlight = request;
    try {
      return await request;
    } finally {
      _inFlight = null;
    }
  }

  Future<LiveTurnCredentials?> _request(LiveTurnFetcher fetch) async {
    try {
      final LiveTurnCredentials? fresh = await fetch();
      if (fresh != null && fresh.isValidAt(_clock())) {
        _cached = fresh;
        _retryNotBefore = null;
        _warned = false;
        return fresh;
      }
      _noRelay('el backend no tiene relé configurado');
      return null;
    } catch (error) {
      _noRelay('fallo al pedir credenciales: $error');
      return null;
    }
  }

  /// Registra el fallo UNA vez por ventana de backoff: es información de
  /// operación (explica por qué fallan conexiones en móvil), no ruido por
  /// llamada.
  void _noRelay(String reason) {
    _cached = null;
    _retryNotBefore = _clock().add(failureBackoff);
    if (_warned) return;
    _warned = true;
    debugPrint(
      '[live] sin TURN ($reason): se sigue solo con STUN; las conexiones '
      'tras NAT simétrico pueden no establecerse.',
    );
  }

  /// Tira la caché (cierre de sesión, o el relé rechazó las credenciales).
  void invalidate() {
    _cached = null;
    _retryNotBefore = null;
    _warned = false;
  }
}

class LiveIceConfig {
  const LiveIceConfig._();

  /// STUN público de Google. Solo sirve para DESCUBRIR direcciones: no ve ni
  /// transporta el vídeo, así que no compromete la privacidad del medio.
  ///
  /// Va de CONSTANTE y no del backend a propósito: si la callable de TURN
  /// falla, el cliente tiene que conservar al menos el ICE que sí funciona.
  static const List<String> stunUrls = <String>[
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
  ];

  /// ¿Hay relé vigente? La UI lo usa para avisar de que, sin TURN, algunas
  /// conexiones pueden no llegar a establecerse (mejor decirlo que dejar al
  /// usuario mirando una pantalla negra). Es dinámico: hasta que no se piden
  /// credenciales con éxito, es `false`.
  static bool get hasTurn => LiveTurnCache.instance.hasRelay;

  /// Configuración para `createPeerConnection`.
  ///
  /// [turn] son las credenciales efímeras ya obtenidas. Se pasan resueltas (y
  /// no un `Future`) porque los servidores ICE se fijan al CONSTRUIR la
  /// `RTCPeerConnection`: hay que tenerlas antes, no después.
  static Map<String, dynamic> build({LiveTurnCredentials? turn}) {
    final List<Map<String, dynamic>> servers = <Map<String, dynamic>>[
      <String, dynamic>{'urls': stunUrls},
      if (turn != null && turn.isUsable)
        <String, dynamic>{
          'urls': turn.urls,
          'username': turn.username,
          'credential': turn.credential,
        },
    ];

    return <String, dynamic>{
      'iceServers': servers,
      // Unified Plan: el estándar actual. Plan B está obsoleto y algunos
      // navegadores/SDK ya no lo aceptan.
      'sdpSemantics': 'unified-plan',
      // Recolectar candidatos ya durante la creación de la oferta acorta el
      // establecimiento: importa cuando la sesión dura solo 3 minutos.
      'iceCandidatePoolSize': 2,
      // No forzamos 'relay': con `all` se intenta primero la ruta directa
      // (mejor latencia y coste cero) y solo se cae al relé si hace falta.
      'iceTransportPolicy': 'all',
    };
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
