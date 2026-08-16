import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../ads/presentation/feed_native_ad_card.dart';
import '../../ai_visual/data/ai_visual_service.dart';
import '../../anti_ghosting/data/anti_ghosting_analytics.dart';
import '../../anti_ghosting/data/pending_conversations_controller.dart';
import '../../anti_ghosting/domain/anti_ghosting_config.dart';
import '../../anti_ghosting/presentation/pending_limit_sheet.dart';
import '../../auth/data/device_location_source.dart';
import '../../auth/data/location_refresh_service.dart';
import '../../auth/data/platform_place_resolver.dart';
import '../../auth/domain/resolved_place.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/location_refresh_policy.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/presentation/chat_detail_screen.dart';
import '../../match/data/match_service.dart';
import '../../match/domain/like.dart';
import '../../match/domain/match_flow_result.dart';
import '../../match/presentation/match_created_dialog.dart';
import '../../match/presentation/photo_response_sheet.dart';
import '../../match/presentation/prompt_response_sheet.dart';
import '../../profile/domain/profile_summary.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/presentation/profile_view_screen.dart';
import '../../safety/presentation/safety_actions.dart';
import '../../social/domain/intent_mode.dart';
import '../../monetization/data/boost_service.dart';
import '../../monetization/domain/boost.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../../stories/data/story_service.dart';
import '../../stories/domain/story.dart';
import '../../stories/domain/story_wall.dart';
import '../../stories/presentation/blind_story_viewer_screen.dart';
import '../../stories/presentation/blind_wall_controller.dart';
import '../../stories/presentation/my_story_button.dart';
import '../../stories/presentation/profile_reveal_screen.dart';
import '../../stories/presentation/story_stack_card.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_image.dart';
import '../../../widgets/attra_states.dart';
import '../data/feed_metrics_service.dart';
import '../data/ranking_signals_repository.dart';
import '../domain/boost_ranker.dart';
import '../domain/feed_filter.dart';
import '../domain/feed_filters.dart';
import '../domain/liked_me_ranker.dart';
import '../domain/ranking.dart';
import '../domain/ranking_config.dart';
import '../domain/rewind_policy.dart';
import '../domain/slow_dating.dart';
import 'filters_screen.dart';

/// Feed de descubrimiento. Cada tarjeta es un perfil con scroll vertical
/// (todas las fotos + datos, estilo Hinge) y swipe horizontal para
/// pasar (izquierda) o dar like (derecha). Filtrado por interés de género.
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.user,
    required this.onLoadSeedProfiles,
    required this.matchService,
    this.sparkService,
    this.sparkEnabled = false,
    required this.chatService,
    this.attrasBalance = 0,
    this.canComment = false,
    this.reloadToken = 0,
    this.visualSearchToken = 0,
    this.storyService,
    this.isPlus = false,
    this.canRewind = false,
    this.rewindUnlimited = false,
    this.onOpenUpgrade,
    this.aiVisualService,
    this.canUseVisualMatch = false,
    this.canSeeLikedMe = false,
    this.metrics,
    this.boostService,
    this.adsEnabled = false,
    this.canUseTravelMode = false,
    this.onOpenTravel,
    this.rankingSignals,
    this.rankingConfig = const RankingConfig(),
    this.antiGhostingConfig,
    this.pendingController,
    this.isBusy = false,
    this.isPro = false,
    this.onOpenChats,
    this.onOpenGroups,
    this.onDeviceLocation,
    this.locationSource,
    this.placeResolver,
  });

  /// Attra Clear §2: límite suave de conversaciones pendientes. Si null o
  /// deshabilitado, el feed no aplica ningún bloqueo (comportamiento previo).
  final AntiGhostingConfig? antiGhostingConfig;
  final PendingConversationsController? pendingController;

  /// Modo ocupado activo (§4): exime del límite de pendientes (no penaliza).
  final bool isBusy;

  /// Para el límite por plan (free/plus/pro).
  final bool isPro;

  /// Abre la pestaña de chats (CTA "Ver conversaciones").
  final VoidCallback? onOpenChats;

  /// Modo Amigos: abre la pantalla de grupos. Si es null, no se muestra el
  /// acceso a grupos en el feed.
  final VoidCallback? onOpenGroups;

  /// Persiste la ubicación del dispositivo cuando el feed la obtiene o la
  /// refresca: escribe `users/{uid}.location` (con la marca de frescura) y
  /// republica `discovery/{uid}` para que los demás te vean donde estás.
  final PersistDeviceLocation? onDeviceLocation;

  /// Acceso al GPS. Inyectable SOLO para pruebas: en producción es
  /// [GeolocatorLocationSource].
  final DeviceLocationSource? locationSource;

  /// Traduce coordenadas a ciudad/pais. Inyectable porque el geocodificador
  /// del sistema es canal nativo y en `flutter test` no existe.
  final PlaceResolver? placeResolver;

  final AppUser? user;
  final Future<List<SeedProfile>> Function() onLoadSeedProfiles;
  final MatchService matchService;

  /// Attra Spark tras un match. El diálogo de match del feed no lo ofrecía
  /// mientras que el de "Conexiones" sí: la misma acción se comportaba distinto
  /// según de dónde vinieras.
  final SparkService? sparkService;
  final bool sparkEnabled;
  final ChatService chatService;
  final StoryService? storyService;
  final int attrasBalance;

  /// Cambia (lo incrementa HomeShell al abrir la pestaña Feed) para forzar una
  /// recarga que re-aplica la exclusion (p.ej. tras un match desde Likes).
  final int reloadToken;

  /// Se incrementa desde fuera (pantalla de IA visual) para ACTIVAR el filtro
  /// "Solo parecidos a mi referencia" y recargar. Antes ese botón solo enseñaba
  /// un aviso pidiendo al usuario que buscara el filtro él mismo.
  final int visualSearchToken;

  /// Comentar una foto es una función Plus. Si es false, el sheet bloquea el
  /// comentario pero permite enviar Like/Attra sin texto.
  final bool canComment;

  /// Si el usuario es Plus (desbloquea filtros avanzados).
  final bool isPlus;

  /// Rewind del feed: Plus/Premium pueden volver un paso; Pro guarda historial
  /// de la sesion sin limite. Free no puede usarlo.
  final bool canRewind;
  final bool rewindUnlimited;
  final VoidCallback? onOpenUpgrade;

  /// IA visual (Pro + consentimiento + referencia) para ordenar por parecido.
  final AiVisualService? aiVisualService;
  final bool canUseVisualMatch;

  /// Plus/Pro: muestra en el feed quién te ha dado like (badge + realce +
  /// prioridad al frente). Free no lo ve (muro en la pestaña Likes).
  final bool canSeeLikedMe;

  /// Telemetría del embudo + impresiones (opcional; null = no se registra nada).
  final FeedMetricsService? metrics;

  /// Boosts consumibles: lectura de boosts activos + registro de impresiones.
  final BoostService? boostService;

  /// Muestra ad cards nativas en el feed (ya viene resuelto: flag activo Y el
  /// usuario NO es Plus/Pro). Si false, el feed va sin anuncios.
  final bool adsEnabled;

  /// Modo viajes (Plus/Pro): botón para cambiar la ubicación del feed.
  final bool canUseTravelMode;
  final VoidCallback? onOpenTravel;

  /// Ranking inteligente: señales server-side (prefetch) + config remota. Si
  /// null o `rankingConfig.enabled == false`, el feed usa el orden orgánico
  /// base (rollback seguro).
  final RankingSignalsRepository? rankingSignals;
  final RankingConfig rankingConfig;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

/// Resultado de una búsqueda IA del feed (foto de referencia o descripción).
///
/// Antes estas búsquedas devolvían simplemente una lista vacía en TODOS los
/// casos de fallo (motor caído, función sin desplegar, sin red, nadie supera el
/// umbral) y el feed acababa en el estado genérico "No hay más personas por el
/// momento": el usuario no podía saber que tenía un filtro IA vaciándole el
/// feed ni por qué.
enum _AiSearchStatus {
  /// La IA respondió y hay resultados.
  ok,

  /// La IA respondió pero nadie supera el umbral de parecido/encaje.
  noMatches,

  /// El motor no devolvió ranking (deshabilitado, sin referencia, función no
  /// desplegada, sin red...).
  unavailable,

  /// La llamada lanzó excepción.
  failed,

  /// Hay un filtro IA guardado pero el plan actual ya no lo incluye, así que NO
  /// se ha aplicado (el feed va sin él).
  notEntitled,
}

/// Estado de la búsqueda IA de la última carga (null = ninguna pedida).
class _AiSearchState {
  const _AiSearchState({
    required this.byPrompt,
    required this.status,
    this.query = '',
  });

  /// true = búsqueda por descripción; false = por foto de referencia.
  final bool byPrompt;
  final _AiSearchStatus status;
  final String query;

  /// Etiqueta corta para el banner del feed.
  String get label => byPrompt
      ? (query.isEmpty ? 'Búsqueda por descripción' : '«$query»')
      : 'Solo parecidos a mi referencia';
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<SeedProfile> _profiles = const <SeedProfile>[];
  int _index = 0;
  Set<String> _excluded = const <String>{};
  Set<String> _likedMeUids = const <String>{};

  /// "Segunda vuelta": cuando se acaba el feed, re-ver los perfiles que pasaste
  /// (dislikes). Se activa desde el estado vacío. `_dislikedUids` se refresca en
  /// cada carga para saber si hay pases que reconsiderar.
  bool _secondRound = false;
  Set<String> _dislikedUids = const <String>{};
  Map<String, ActiveBoost> _activeBoostsByUid = const <String, ActiveBoost>{};
  bool _storiesEnabled = false;

  /// Ya ha llegado el primer evento del stream de historias. Sin esto, entre que
  /// el pool está listo y llegan las historias se pintaba un instante el feed de
  /// PERFILES: justo lo que el muro a ciegas evita.
  bool _storiesLoaded = false;

  /// El flag remoto `storiesEnabled` ya ha contestado. La barrera del "a ciegas"
  /// tiene que esperarlo: mientras el `get()` está en vuelo `_storyWallActive`
  /// es false, y si el pool gana la carrera se pintaba la ficha COMPLETA (bio,
  /// trabajo, estudios, verificación…) de la primera persona.
  bool _storiesFlagResolved = false;

  /// El stream de historias está CAÍDO, que no es lo mismo que "nadie ha
  /// publicado": un error termina la suscripción de Firestore, así que sin
  /// reintento Discover se quedaba vacío el resto de la sesión mientras el
  /// estado vacío mentía sobre la causa.
  bool _storiesUnavailable = false;
  int _storiesRetries = 0;
  Timer? _storiesRetryTimer;

  /// Reintento de la LECTURA del flag remoto. Un fallo ahí apaga el muro, y
  /// apagar el muro es enseñar la ficha completa de la gente: no puede quedarse
  /// así el resto de la sesión por un bache de red.
  int _storiesFlagRetries = 0;
  Timer? _storiesFlagRetryTimer;

  // Stories vivas agrupadas por dueño: es lo que decide QUIÉN entra en el muro
  // y cuántas hojas tiene su pila.
  Map<String, List<Story>> _storiesByOwner = const <String, List<Story>>{};

  /// Pool YA filtrado y ordenado por el pipeline completo (filtros duros,
  /// ranking orgánico, Boost, modo viaje, Slow Dating, IA, "te dio like").
  ///
  /// Se guarda aparte de [_profiles] porque Discover ya no muestra perfiles
  /// sino HISTORIAS: [_profiles] es este pool cruzado con quien tiene alguna
  /// historia viva. Al llegar historias nuevas por el stream basta con volver a
  /// cruzar, sin repetir todo el pipeline (que hace lecturas de red).
  List<SeedProfile> _rankedPool = const <SeedProfile>[];

  /// Uids ya decididos en esta sesión (like, pase, Attra o "vistas todas sus
  /// historias"). El muro se recompone con CADA snapshot del stream global de
  /// historias y, sin esta memoria, el índice caía a 0 y volvía a enseñar —y a
  /// dejar swipear otra vez— a quien ya se había decidido.
  final Set<String> _consumed = <String>{};

  /// Último perfil por el que se ha contado impresión. La recomposición del muro
  /// es constante (basta con que alguien, en cualquier parte, vea una historia):
  /// sin esta guarda cada snapshot mandaba otra llamada de impresión de Boost
  /// por red para el mismo perfil.
  String _impressedUid = '';

  StreamSubscription<Map<String, List<Story>>>? _storiesSub;
  Timer? _storiesTimeout;
  // Stories ya vistas (por id) en esta sesión: la pila del muro se atenúa pero
  // se puede reabrir cuantas veces se quiera.
  final Set<String> _seenStoryIds = <String>{};

  /// Puente con el visor a ciegas. El visor NO habla con el backend: le devuelve
  /// las acciones a este estado, que es quien tiene el gate de likes, las
  /// métricas, el rewind y los anuncios. Se crea perezosamente (solo si el muro
  /// llega a abrirse) y vive mientras viva el feed.
  BlindWallController? _blindWall;
  bool _blindViewerOpen = false;

  bool _rewinding = false;

  /// Marcha atrás de esta sesión. La REGLA (qué guarda cada plan, qué se puede
  /// deshacer, qué se le dice al usuario) vive en [RewindState], que es puro y
  /// testeable; aquí solo se guarda el historial y se aplica el resultado.
  ///
  /// El tramo NO se guarda dentro: se recalcula en [_rewindState] desde los
  /// props, porque el plan cambia en caliente (se compra Plus desde el paywall,
  /// o caduca una suscripción con la app abierta) y un tramo congelado en el
  /// `initState` seguiría mandando al paywall a quien acaba de pagar.
  RewindState _rewind = const RewindState();
  FeedFilters _filters = const FeedFilters();

  /// Estado de la búsqueda IA de la última carga. null = no hay ninguna pedida.
  /// Es lo que permite explicar un feed vacío causado por el filtro IA en vez
  /// de soltar el genérico "No hay más personas por el momento".
  _AiSearchState? _aiSearch;

  // Ubicación del dispositivo como RESPALDO mientras la escritura en
  // `users/{uid}` no ha vuelto: así la distancia del feed siempre tiene un "yo"
  // con el que trabajar.
  //
  // Solo se adopta una lectura que se haya GUARDADO (o cuando no había ninguna
  // coordenada). Si no, el feed se filtraba desde un punto que `discovery/{uid}`
  // no publica: dabas likes a gente que, con su radio, no te podía ver. Peor aún
  // con una lectura que la política acababa de rechazar por ser un retroceso
  // (`cacheOlderThanStored`), que además ganaba al documento el resto de la sesión.
  double? _deviceLat;
  double? _deviceLng;

  /// Aviso de ubicación que se está enseñando (permiso denegado, localización
  /// apagada, ubicación rancia que no se puede refrescar). Antes esto no existía:
  /// `_ensureDeviceLocation` se tragaba cualquier fallo y el usuario veía gente
  /// de otra ciudad sin ninguna explicación.
  LocationNotice _locationNotice = LocationNotice.none;

  /// True mientras hay un refresco de ubicación pedido a mano (para el botón).
  bool _locationRefreshing = false;

  /// Coordenadas con las que se filtró la última carga del feed. Sirven para no
  /// recargar cuando la ubicación nueva no cambiaría a quién ves.
  double? _loadedLat;
  double? _loadedLng;

  /// Contador de cargas: solo la ÚLTIMA puede pintar su resultado (ver [_load]).
  int _loadGeneration = 0;

  /// La carga actual ha tenido que ignorar el PAÍS declarado para no quedarse
  /// vacía (ver el respaldo de `_load`). Se cuenta al usuario: un feed con gente
  /// de otro país, sin explicación, parece un error.
  bool _countryFallback = false;

  /// Lat efectiva del usuario: la del dispositivo si la acabamos de leer y aún
  /// no ha vuelto del backend, y si no la guardada.
  ///
  /// El orden importa: la lectura de esta sesión es MÁS reciente que la del
  /// documento, y con el orden contrario un refresco no se notaba en el feed
  /// hasta que Firestore devolvía el usuario recargado.
  double? get _effectiveLat => _deviceLat ?? widget.user?.latitude;
  double? get _effectiveLng => _deviceLng ?? widget.user?.longitude;

  /// Refresco de ubicación. La DECISIÓN (¿toca? ¿está rancia? ¿hay permiso?)
  /// vive en [LocationRefreshPolicy], que es lógica pura y testeable; aquí solo
  /// se engancha.
  late final LocationRefreshService _locationService = LocationRefreshService(
    source: widget.locationSource ?? const GeolocatorLocationSource(),
    // Inyectable para los tests: el geocodificador es canal nativo.
    placeResolver: widget.placeResolver ?? const PlatformPlaceResolver(),
    persist: ({
      required double latitude,
      required double longitude,
      required DateTime fixedAt,
      String? permissionStatus,
      bool? permissionGranted,
      ResolvedPlace? place,
    }) async {
      final PersistDeviceLocation? save = widget.onDeviceLocation;
      // Sin nadie que persista, la ubicación NO se ha guardado ni se ha
      // republicado en discovery: fingir lo contrario haría que el servicio diera
      // por fresca una ubicación que sigue siendo la vieja.
      if (save == null) {
        throw StateError('feed sin onDeviceLocation: no se puede guardar');
      }
      await save(
        latitude: latitude,
        longitude: longitude,
        fixedAt: fixedAt,
        permissionStatus: permissionStatus,
        permissionGranted: permissionGranted,
        place: place,
      );
    },
  );

  /// Cuándo dejó la app de estar delante. Un rato largo en el fondo es la señal
  /// de viaje más fiable que tenemos: el reloj a secas dejaba fuera cualquier
  /// trayecto de menos de 4 h (Valencia→Madrid en AVE son 1 h 50 min).
  DateTime? _backgroundSince;

  @override
  void initState() {
    super.initState();
    // El ciclo de vida se observa aquí y no en HomeShell porque el feed vive
    // dentro de un IndexedStack: sigue montado con cualquier pestaña delante, así
    // que recibe `resumed` aunque el usuario vuelva a la app en Chats.
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadStoriesFlag();
    _refreshLocation(LocationRefreshTrigger.appStart);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // `paused`/`hidden` = la app dejó de estar delante de verdad. `inactive` no
    // cuenta: en iOS salta por cualquier interrupción de un segundo.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
      return;
    }
    // Quien viaja abre la app AL LLEGAR: si solo se mirara la ubicación al
    // arrancar, un proceso que lleva días vivo nunca se enteraría del viaje.
    // La tormenta de llamadas la corta el cooldown de la política (`resumed`
    // salta cada vez que se vuelve de otra app).
    if (state == AppLifecycleState.resumed) {
      final DateTime? since = _backgroundSince;
      _backgroundSince = null;
      _refreshLocation(
        LocationRefreshTrigger.appResume,
        // Cuánto ha estado la app fuera: con media hora o más, la política deja
        // de creerse una ubicación de hace 2 h (es el trayecto en tren que no se
        // detectaba de ninguna manera).
        awayFor: since == null ? null : DateTime.now().difference(since),
      );
    }
  }

  /// Refresca la ubicación si la política dice que toca, la guarda (lo que
  /// republica `discovery/{uid}`) y recarga el feed si las coordenadas cambiaron.
  ///
  /// Best-effort para el usuario, pero NO silencioso: lo que no se puede
  /// arreglar solo (permiso denegado, localización apagada, ubicación rancia que
  /// no se consigue refrescar) acaba en [_locationNotice].
  /// Devuelve true si el refresco ha acabado recargando el feed (para que quien
  /// llama no lo cargue otra vez).
  Future<bool> _refreshLocation(
    LocationRefreshTrigger trigger, {
    Duration? awayFor,
  }) async {
    final AppUser? user = widget.user;
    if (user == null) return false;
    if (trigger == LocationRefreshTrigger.manual) {
      setState(() => _locationRefreshing = true);
    }
    bool reloaded = false;
    try {
      final LocationRefreshOutcome outcome = await _locationService.refresh(
        stored: user.storedLocation,
        trigger: trigger,
        awayFor: awayFor,
        // Umbral de escritura acorde con el radio del feed: con "Distancia
        // máxima" en 2 km, no guardar un movimiento de 9 km dejaba al usuario
        // likeando a vecinos que, con su radio, no le podían ver.
        moveThresholdKm: _effectiveRadiusKm / 2,
        // El modo viaje NO se puede pisar: la política evita gastar GPS cuando el
        // feed está anclado al destino, y `DiscoveryPublisher` sigue siendo quien
        // decide que viajando no se publican coordenadas.
        travelActive: user.isTraveling,
      );
      if (!mounted) return false;

      final LocationFix? fix = outcome.fix;
      // Solo se adopta como "yo" una lectura que YA está guardada (o si no había
      // coordenadas de ninguna clase): así el punto desde el que filtras es el
      // mismo que `discovery/{uid}` publica y la visibilidad es simétrica.
      final bool adopt = fix != null &&
          (outcome.persisted || !user.storedLocation.hasCoordinates);
      final bool needsReload = adopt && _feedWouldChangeWith(fix);
      setState(() {
        _locationRefreshing = false;
        if (adopt) {
          _deviceLat = fix.latitude;
          _deviceLng = fix.longitude;
        }
        // Con otro intento ya en curso no hay información nueva que enseñar:
        // sobrescribir el aviso solo lo haría parpadear. Una ronda frenada por el
        // cooldown SÍ trae información (permiso y frescura), y si la ubicación
        // sigue rancia el usuario merece verlo y poder forzarlo.
        if (outcome.reason != LocationRefreshReason.inFlight) {
          _locationNotice = outcome.notice;
        }
      });

      // Solo se recarga el feed si el "yo" cambió: `_load()` hace lecturas de red
      // y el resultado sería idéntico con las mismas coordenadas.
      if (needsReload) {
        reloaded = true;
        await _load();
      }
    } catch (error) {
      // La ubicación es best-effort para el feed: un fallo del canal nativo no
      // puede tumbar la pantalla (ni dejar un error asíncrono suelto en
      // `initState`). Lo que el usuario tiene que saber ya está en el aviso.
      if (kDebugMode) {
        debugPrint('[Attra][Ubicación] refresco fallido: $error');
      }
    } finally {
      // En un `finally` a propósito: si el intento falla o se queda sin
      // completar, el aviso se quedaba con el spinner puesto y `onTap` en null,
      // es decir, sin ninguna forma de reintentarlo.
      if (mounted && _locationRefreshing) {
        setState(() => _locationRefreshing = false);
      }
    }
    return reloaded;
  }

  /// Radio (km) con el que el feed está midiendo distancias ahora mismo.
  double get _effectiveRadiusKm => (_filters.maxDistanceKm ??
          widget.user?.maxDistanceKm ??
          FeedFilter.defaultRadiusKm)
      .toDouble();

  /// ¿Cambiaría el feed si se recargara con esta lectura?
  ///
  /// Evita una segunda carga (con sus lecturas de red) en cada arranque: lo
  /// normal es que el fix confirme el sitio donde el feed ya te estaba situando.
  ///
  /// El umbral es el mismo con el que se decide GUARDAR: `_load()` es
  /// DESTRUCTIVO (vacía el mazo, vuelve a la primera carta y borra el historial
  /// de rewind), así que recargar por 1 km era perder la sesión de swipe de quien
  /// va en autobús por su ciudad, y encima sin poder cambiar a quién ve (el radio
  /// mínimo son kilómetros y las coordenadas públicas se redondean a ~1,1 km).
  bool _feedWouldChangeWith(LocationFix fix) {
    // Viajando el feed usa el país de destino y descarta la latitud/longitud:
    // recargar por una coordenada nueva no cambiaría ni un perfil.
    if (widget.user?.isTraveling ?? false) return false;
    final double? lat = _loadedLat;
    final double? lng = _loadedLng;
    // El feed se cargó SIN ubicación: pasa de filtrar por país a filtrar por
    // radio, así que sí cambia.
    if (lat == null || lng == null) return true;
    return LocationRefreshPolicy.distanceKm(lat, lng, fix.latitude,
            fix.longitude) >=
        LocationRefreshPolicy.significantMoveKm;
  }

  /// Recarga que pide el usuario desde un estado vacío. Además de volver a
  /// consultar el feed, vuelve a mirar dónde está: un feed vacío por estar
  /// publicado en la ciudad de la que te mudaste se ve EXACTAMENTE igual que un
  /// feed vacío de verdad, y antes la única salida era el modo viaje a mano.
  ///
  /// En serie y no en paralelo: lanzados a la vez, el refresco leía las
  /// coordenadas de la carga ANTERIOR y disparaba un segundo `_load()` solapado
  /// con el primero.
  Future<void> _reloadFeed() async {
    final bool reloaded = await _refreshLocation(
        LocationRefreshTrigger.feedReload);
    if (!reloaded && mounted) await _load();
  }

  /// Abre el diálogo del sistema (o los ajustes del sistema si ya está bloqueado)
  /// desde el aviso del feed. Es un gesto EXPLÍCITO del usuario sobre un texto
  /// que explica para qué se usa la ubicación: pedir el permiso al abrir el feed,
  /// sin contexto, es justo lo que iOS penaliza en revisión.
  Future<void> _onLocationNoticeTap() async {
    if (_locationNotice == LocationNotice.permissionBlocked ||
        _locationNotice == LocationNotice.serviceDisabled) {
      try {
        if (_locationNotice == LocationNotice.serviceDisabled) {
          await Geolocator.openLocationSettings();
        } else {
          await Geolocator.openAppSettings();
        }
      } catch (_) {/* sin ajustes que abrir: el aviso sigue ahí */}
      return;
    }
    await _refreshLocation(LocationRefreshTrigger.manual);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Vuelca impresiones pendientes (no perder telemetría al cerrar).
    widget.metrics?.flush();
    _storiesSub?.cancel();
    _storiesTimeout?.cancel();
    _storiesRetryTimer?.cancel();
    _storiesFlagRetryTimer?.cancel();
    _blindWall?.dispose();
    super.dispose();
  }

  /// Umbral de parecido (similitud coseno) para considerar a alguien "similar".
  /// El embedding multimodal de Vertex es ESTÉTICO (composición, estilo…): dos
  /// fotos de la misma persona suelen rondar 0.5-0.8 y el mismo "tipo" 0.45-0.6.
  /// 0.55 mantiene precision suficiente: Bella da ~0.658 y Ariel ~0.557 con
  /// esta referencia, mientras los mocks de viaje probados quedan por debajo.
  static const double _kVisualThreshold = 0.55;

  /// FILTRA el feed dejando SOLO los que se parecen a la foto de referencia
  /// (>= [_kVisualThreshold]), ordenados de más a menos parecido.
  ///
  /// Si el motor no esta disponible, devuelve una lista vacia. Al aplicar el
  /// filtro visual es peor mostrar el feed organico como falso positivo. Ahora
  /// devuelve TAMBIÉN el motivo, para que el estado vacío pueda explicarlo.
  Future<({List<SeedProfile> profiles, _AiSearchStatus status})>
      _sortByVisualReference(List<SeedProfile> profiles) async {
    // Sin candidatos previos la culpa no es de la IA (son los otros filtros).
    if (profiles.isEmpty) {
      return (profiles: profiles, status: _AiSearchStatus.ok);
    }
    try {
      final List<VisualMatch> ranking = await widget.aiVisualService!
          .getVisualMatches(profiles.map((SeedProfile p) => p.id).toList());
      // Motor no disponible (Vertex deshabilitado / sin referencia): sin falsos
      // positivos.
      if (ranking.isEmpty) {
        return (
          profiles: const <SeedProfile>[],
          status: _AiSearchStatus.unavailable
        );
      }

      if (kDebugMode) {
        for (final VisualMatch m in ranking) {
          debugPrint('[IA visual] ${m.uid}: ${m.score.toStringAsFixed(3)}');
        }
      }

      final Map<String, SeedProfile> byId = <String, SeedProfile>{
        for (final SeedProfile p in profiles) p.id: p,
      };
      // Solo los que superan el umbral, en orden de parecido (desc).
      final List<SeedProfile> matches = <SeedProfile>[
        for (final VisualMatch m in ranking)
          if (m.score >= _kVisualThreshold && byId.containsKey(m.uid))
            byId[m.uid]!,
      ];
      return (
        profiles: matches,
        status:
            matches.isEmpty ? _AiSearchStatus.noMatches : _AiSearchStatus.ok,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IA visual] error al ordenar: $e');
      }
      return (profiles: const <SeedProfile>[], status: _AiSearchStatus.failed);
    }
  }

  /// Umbral mínimo de encaje para la búsqueda por prompt (combinado foto+datos).
  static const double _kPromptThreshold = 0.5;

  /// FILTRA el feed dejando SOLO los que encajan con la descripción (prompt),
  /// ordenados por encaje. Si el motor no está disponible, devuelve vacío (mejor
  /// que mostrar falsos positivos) junto con el motivo, para poder explicárselo
  /// al usuario en vez de dejarle un feed en blanco.
  Future<({List<SeedProfile> profiles, _AiSearchStatus status})> _sortByPrompt(
      List<SeedProfile> profiles) async {
    if (profiles.isEmpty) {
      return (profiles: profiles, status: _AiSearchStatus.ok);
    }
    try {
      final List<PromptMatch> ranking = await widget.aiVisualService!
          .getPromptMatches(_filters.promptQuery.trim(),
              profiles.map((SeedProfile p) => p.id).toList());
      if (ranking.isEmpty) {
        return (
          profiles: const <SeedProfile>[],
          status: _AiSearchStatus.unavailable
        );
      }
      final Map<String, SeedProfile> byId = <String, SeedProfile>{
        for (final SeedProfile p in profiles) p.id: p,
      };
      final List<SeedProfile> matches = <SeedProfile>[
        for (final PromptMatch m in ranking)
          if (m.score >= _kPromptThreshold && byId.containsKey(m.uid))
            byId[m.uid]!,
      ];
      return (
        profiles: matches,
        status:
            matches.isEmpty ? _AiSearchStatus.noMatches : _AiSearchStatus.ok,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[IA prompt] error: $e');
      return (profiles: const <SeedProfile>[], status: _AiSearchStatus.failed);
    }
  }

  /// Centra el feed en el destino de viaje: deja solo los perfiles del país
  /// elegido y pone delante los de la ciudad. Sin país no filtra (devuelve tal
  /// cual). Comparaciones case-insensitive.
  List<SeedProfile> _applyTravel(List<SeedProfile> profiles) {
    // País normalizado (Italy=Italia, Spain=España…) para no vaciar el feed por
    // diferencias de idioma entre el destino y los perfiles.
    final String country =
        FeedFilter.canonCountry(widget.user?.travelCountry ?? '');
    final String city = _canonCity(widget.user?.travelCity ?? '');
    if (country.isEmpty) return profiles;
    final List<SeedProfile> inCountry = profiles
        .where((SeedProfile p) => FeedFilter.canonCountry(p.country) == country)
        .toList(growable: false);
    if (city.isEmpty) return inCountry;
    inCountry.sort((SeedProfile a, SeedProfile b) {
      final bool aCity = _canonCity(a.city) == city;
      final bool bCity = _canonCity(b.city) == city;
      if (aCity == bCity) return 0;
      return aCity ? -1 : 1;
    });
    return inCountry;
  }

  /// Normaliza ciudad para comparar pese al idioma (Rome=Roma, etc.).
  static String _canonCity(String raw) {
    final String s = raw.trim().toLowerCase();
    const Map<String, String> aliases = <String, String>{
      'roma': 'rome',
      'rome': 'rome',
      'milán': 'milan',
      'milan': 'milan',
      'milano': 'milan',
      'londres': 'london',
      'london': 'london',
      'lisboa': 'lisbon',
      'lisbon': 'lisbon',
      'munich': 'munich',
      'múnich': 'munich',
      'münchen': 'munich',
    };
    return aliases[s] ?? s;
  }

  /// Muro de historias activo.
  ///
  /// Con `storiesEnabled` APAGADO (que es el default) Discover sigue siendo el
  /// feed de perfiles de toda la vida. Si el muro se aplicara igualmente, la
  /// pantalla estaría vacía para todo el mundo hasta que alguien encendiera el
  /// flag: el rediseño no puede depender de una bandera remota para que la app
  /// tenga un Discover usable.
  bool get _storyWallActive => _storiesEnabled && widget.storyService != null;

  Future<void> _loadStoriesFlag() async {
    final StoryService? svc = widget.storyService;
    if (svc == null) {
      // Sin servicio no hay muro posible y no hay nada que reintentar.
      if (!mounted) return;
      setState(() {
        _storiesFlagResolved = true;
        _applyStoryWall();
      });
      _afterWallChanged();
      return;
    }
    bool enabled;
    try {
      // Con timeout: la barrera del "a ciegas" espera a este flag, así que un
      // `get()` que tarda en volver (arranque en frío, red mala) dejaría
      // Discover en el esqueleto. Agotarlo cuenta como fallo, no como "apagado".
      enabled = await svc
          .storiesEnabled()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // No se ha podido leer el flag, que NO es lo mismo que estar apagado. Se
      // sigue pintando el feed de perfiles (el default, para no dejar Discover
      // en el esqueleto sin red), pero se reintenta con espera creciente igual
      // que el stream de historias: antes un solo bache dejaba el muro apagado
      // el resto de la sesión, enseñando la ficha completa de cada persona.
      if (!mounted) return;
      setState(() {
        _storiesFlagResolved = true;
        _applyStoryWall();
      });
      _afterWallChanged();
      _scheduleStoriesFlagRetry();
      return;
    }
    if (!mounted) return;
    _storiesFlagRetries = 0;
    setState(() {
      _storiesEnabled = enabled;
      _storiesFlagResolved = true;
      // El flag llega DESPUÉS de la primera carga: hay que rehacer el muro o el
      // pool ya cargado se quedaría pintado como feed de perfiles.
      _applyStoryWall();
    });
    _afterWallChanged();
    if (enabled) _bindStories();
  }

  /// Reintento con espera creciente (2, 4, 8, 16 y 32 s) de la LECTURA del flag.
  void _scheduleStoriesFlagRetry() {
    _storiesFlagRetryTimer?.cancel();
    _storiesFlagRetries = (_storiesFlagRetries + 1).clamp(1, 5);
    _storiesFlagRetryTimer =
        Timer(Duration(seconds: 1 << _storiesFlagRetries), () {
      if (mounted && !_storiesEnabled) _loadStoriesFlag();
    });
  }

  /// Escucha las historias vivas agrupadas por dueño: es lo que define el muro
  /// (quién aparece) y el grosor de cada pila (cuántas tiene).
  void _bindStories() {
    final StoryService? svc = widget.storyService;
    final String myUid = widget.user?.uid ?? '';
    if (svc == null) return;
    _storiesSub?.cancel();
    // TODAS las historias vivas de cada persona, no solo la más reciente:
    // `observeLiveStories` colapsa a una por dueño porque nació con el límite
    // de una historia por usuario, y el muro necesita apilarlas y pasarlas una
    // a una en el visor.
    // Red de seguridad: si el stream no contesta (sin red, reglas, permisos),
    // el muro se marca como "cargado" igualmente. Sin esto Discover se quedaba
    // en el esqueleto para siempre y no había forma de saber que estaba roto.
    _storiesTimeout?.cancel();
    _storiesTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && !_storiesLoaded) setState(() => _storiesLoaded = true);
    });
    _storiesRetryTimer?.cancel();
    _storiesSub = svc
        .observeLiveStoriesByOwner(
      excludeUid: myUid,
      // Prefiltro barato, NO la red de seguridad: la suscripción se abre una vez
      // y se queda con el `_excluded` de ese instante (vacío mientras `_load`
      // hace sus lecturas), y `_load` lo reemplaza además por otro Set. El
      // filtro que de verdad manda es el de `_applyStoryWall`.
      excludedOwners: _excluded,
    )
        .listen(
      (Map<String, List<Story>> byOwner) {
        if (!mounted) return;
        _storiesTimeout?.cancel();
        _storiesRetries = 0;
        setState(() {
          _storiesByOwner = byOwner;
          _storiesLoaded = true;
          _storiesUnavailable = false;
          // Alguien acaba de publicar (o se le caducó): el muro se rehace sin
          // volver a pedir el pool, que cuesta varias lecturas de red.
          _applyStoryWall();
        });
        _afterWallChanged();
      },
      onError: (Object _) {
        // Un error TERMINA la suscripción de Firestore. Antes esto se trataba
        // como definitivo (solo `_storiesLoaded = true`) y un fallo pasajero
        // —token que se refresca, `resource-exhausted`, un bache de red— dejaba
        // Discover vacío hasta reiniciar la app, porque nada volvía a llamar a
        // `_bindStories`. Ahora se reintenta con espera creciente y el estado
        // vacío dice la verdad.
        _storiesTimeout?.cancel();
        _storiesSub?.cancel();
        _storiesSub = null;
        if (!mounted) return;
        setState(() {
          _storiesLoaded = true;
          _storiesUnavailable = true;
        });
        _scheduleStoriesRetry();
      },
    );
  }

  /// Reintento con espera creciente (2, 4, 8, 16 y 32 s) de la suscripción de
  /// historias. La cuenta se reinicia con el primer snapshot bueno.
  void _scheduleStoriesRetry() {
    _storiesRetryTimer?.cancel();
    _storiesRetries = (_storiesRetries + 1).clamp(1, 5);
    final Duration wait = Duration(seconds: 1 << _storiesRetries);
    _storiesRetryTimer = Timer(wait, () {
      if (mounted && _storyWallActive && _storiesSub == null) _bindStories();
    });
  }

  /// Recarga el muro ENTERO: pool y suscripción de historias. El botón de
  /// "Recargar" solo llamaba a `_load()`, que no resuscribe el stream, así que
  /// con el stream caído se podía pulsar indefinidamente sin que cambiara nada.
  void _reloadWall() {
    if (_storyWallActive && _storiesSub == null) _bindStories();
    _load();
  }

  /// Cierra un recálculo del muro hecho FUERA de `_load`: precarga la siguiente
  /// portada y cuenta la impresión de quien queda a la vista.
  ///
  /// `_load` solo puede contar la impresión de lo que ya hay pintado, y con el
  /// muro activo no hay nadie hasta que llega el primer snapshot de historias:
  /// la impresión del perfil en cabeza —que es justo donde el Boost pagado
  /// coloca a quien lo compró— no se registraba nunca.
  void _afterWallChanged() {
    _precacheNext();
    _recordCurrentImpression();
  }

  /// True si TODAS las historias vivas de [ownerUid] ya se han visto (la pila se
  /// atenúa, pero se puede reabrir sin límite).
  bool _ownerStoriesSeen(String ownerUid) {
    final List<Story>? stories = _storiesByOwner[ownerUid];
    if (stories == null || stories.isEmpty) return false;
    return stories.every((Story s) => _seenStoryIds.contains(s.storyId));
  }

  /// Marca historias como vistas y avisa al backend (contador de vistas).
  ///
  /// El repintado va POST-FRAME porque esto lo llama el visor mientras se está
  /// construyendo: un setState en ese momento revienta con "called during
  /// build".
  void _markStoriesSeen(List<Story> stories) {
    bool changed = false;
    for (final Story s in stories) {
      if (_seenStoryIds.add(s.storyId)) {
        changed = true;
        widget.storyService?.viewStory(s.storyId).catchError((_) {});
      }
    }
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Persona que el visor a ciegas debe estar enseñando: la del índice actual
  /// del feed. Solo nombre, edad e historias; el resto es la recompensa.
  BlindWallPerson? get _currentBlindPerson {
    if (_index < 0 || _index >= _profiles.length) return null;
    final SeedProfile profile = _profiles[_index];
    final List<Story> stories =
        _storiesByOwner[profile.id] ?? const <Story>[];
    if (stories.isEmpty) return null;
    return BlindWallPerson(
      uid: profile.id,
      displayName: profile.displayName,
      age: profile.age,
      stories: stories,
    );
  }

  /// Vuelca el estado del feed al visor. Se llama post-frame en cada build: el
  /// controlador ignora los volcados que no cambian nada.
  void _syncBlindWall() {
    final BlindWallController? wall = _blindWall;
    if (wall == null) return;
    final BlindWallPerson? person = _currentBlindPerson;
    wall.sync(
      person: person,
      // El visor se cierra solo cuando toca anuncio intercalado o cuando se
      // acaba el muro: son estados del FEED, no del visor.
      shouldClose: _pendingAd || person == null,
      // La marcha atrás también es estado del feed: el visor pinta el botón con
      // esto y no lleva historial propio.
      rewind: _rewindState,
    );
  }

  void _openBlindViewer() {
    if (_blindViewerOpen || _currentBlindPerson == null) return;
    final BlindWallController wall = _blindWall ??= BlindWallController(
      beforeLike: () async => !await _pendingBlocks(isAttra: false),
      onLike: () async {
        final SeedProfile? p = _profileAtIndex();
        if (p != null) await _onLikeProfile(p);
      },
      onPass: () async {
        final SeedProfile? p = _profileAtIndex();
        if (p != null) await _onPass(p);
      },
      onSuperAttra: () async {
        final SeedProfile? p = _profileAtIndex();
        if (p != null) await _onSuperAttra(p);
      },
      // Ver todas sus historias no es ni like ni pase: solo avanza (y cuenta la
      // impresión, igual que pasar de tarjeta).
      onSkip: _advance,
      onStoriesSeen: _markStoriesSeen,
      // Marcha atrás: MISMO método que el botón de la tarjeta del feed. El visor
      // no puede tener su propio historial ni su propio gate de plan, o serían
      // dos verdades distintas sobre lo mismo.
      onRewind: _onRewind,
      onSafety: () {
        final SeedProfile? p = _profileAtIndex();
        if (p != null) unawaited(_openSafetyMenu(p));
      },
    );
    wall.sync(
      person: _currentBlindPerson,
      shouldClose: false,
      rewind: _rewindState,
    );
    _blindViewerOpen = true;
    // Fundido corto en vez del deslizamiento de página: el visor es Discover a
    // pantalla completa, no otra pantalla a la que "se navega".
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 160),
          pageBuilder: (_, __, ___) => BlindStoryViewerScreen(controller: wall),
          transitionsBuilder:
              (_, Animation<double> animation, __, Widget child) =>
                  FadeTransition(opacity: animation, child: child),
        ))
        .whenComplete(() => _blindViewerOpen = false);
  }

  SeedProfile? _profileAtIndex() =>
      (_index >= 0 && _index < _profiles.length) ? _profiles[_index] : null;

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al volver a la pestaña Feed, recarga y re-excluye (matched/liked/pasados).
    if (oldWidget.reloadToken != widget.reloadToken && !_loading) {
      _load();
    }
    // Modo viaje que se APAGA: mientras viajabas no se publicaban coordenadas y
    // las guardadas pueden ser de antes del viaje. Ahora vuelven a publicarse,
    // así que hay que mirar dónde estás de verdad antes de que los demás te vean
    // en la ciudad de la que te fuiste.
    final bool wasTraveling = oldWidget.user?.isTraveling ?? false;
    final bool isTraveling = widget.user?.isTraveling ?? false;
    if (wasTraveling && !isTraveling) {
      _refreshLocation(LocationRefreshTrigger.travelEnded);
    }
    // El documento ya trae la ubicación que habíamos adoptado: el respaldo deja
    // de hacer falta y se suelta. Si no, una lectura de esta sesión mandaba sobre
    // el documento el resto de la sesión, incluso cuando otro dispositivo
    // escribiera una posterior.
    final double? deviceLat = _deviceLat;
    final double? deviceLng = _deviceLng;
    final double? docLat = widget.user?.latitude;
    final double? docLng = widget.user?.longitude;
    if (deviceLat != null &&
        deviceLng != null &&
        docLat != null &&
        docLng != null &&
        LocationRefreshPolicy.distanceKm(deviceLat, deviceLng, docLat, docLng) <
            LocationRefreshPolicy.minMoveKm) {
      setState(() {
        _deviceLat = null;
        _deviceLng = null;
      });
    }
    // Petición externa de "buscar parecidos a mi referencia".
    if (oldWidget.visualSearchToken != widget.visualSearchToken &&
        widget.visualSearchToken > 0) {
      setState(() {
        _filters = _filters.copyWith(sortByVisualReference: true);
      });
      _load();
    }
  }

  /// Entra en la "segunda vuelta": re-ver los perfiles que pasaste.
  void _enterSecondRound() {
    setState(() => _secondRound = true);
    _load();
  }

  /// Sale de la segunda vuelta y vuelve al feed normal.
  void _exitSecondRound() {
    setState(() => _secondRound = false);
    _load();
  }

  Future<void> _load() async {
    // Generación de la carga: `_load()` se dispara desde varios sitios (arranque,
    // filtros, refresco de ubicación, `reloadToken`) y son varias lecturas de red
    // seguidas, así que dos pueden solaparse. Sin esta marca, la que acabara
    // primero (normalmente la vieja) se quedaba con el `setState` final y el mazo
    // que veía el usuario no correspondía a los filtros de la última petición.
    final int generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _activeBoostsByUid = const <String, ActiveBoost>{};
    });
    try {
      final String myUid = widget.user?.uid ?? '';
      // Se apuntan ANTES del primer await: si no, cualquier ronda de ubicación
      // que terminase durante las lecturas de red veía `_loadedLat == null`,
      // concluía "el feed se cargó sin ubicación" y disparaba una SEGUNDA carga
      // completa. En producción la ronda de ubicación (dos llamadas de canal
      // nativo) siempre gana esa carrera, así que era el doble de lecturas de
      // Firestore en cada apertura de la app, para todo el mundo.
      final bool aiSearchPending = _filters.aiSearchActive &&
          widget.canUseVisualMatch &&
          widget.aiVisualService != null;
      final bool travelingPending =
          !aiSearchPending && (widget.user?.isTraveling ?? false);
      _loadedLat = (travelingPending || aiSearchPending) ? null : _effectiveLat;
      _loadedLng = (travelingPending || aiSearchPending) ? null : _effectiveLng;
      final List<SeedProfile> all = await widget.onLoadSeedProfiles();
      // Excluidos (likeados/pasados/matcheados/bloqueados). Best-effort: si la
      // lectura falla, no vaciamos el feed.
      Set<String> excluded = const <String>{};
      Set<String> disliked = const <String>{};
      if (myUid.isNotEmpty) {
        try {
          excluded = await widget.matchService.fetchExcludedUids(myUid);
        } catch (_) {
          excluded = const <String>{};
        }
        try {
          disliked = await widget.matchService.fetchDislikedUids(myUid);
        } catch (_) {
          disliked = const <String>{};
        }
      }
      // Segunda vuelta: no excluir los pases (para re-verlos). Sigue excluyendo
      // likes/matches/bloqueos (al dar like el backend borra el dislike, así que
      // no reaparecen los ya likeados).
      if (_secondRound) {
        excluded = excluded.difference(disliked);
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      // ¿Hay algún filtro IA PEDIDO? (independiente de si el plan lo permite).
      // Se guarda para poder avisar de que un filtro IA guardado ya no se
      // aplica: antes se ignoraba en silencio.
      final String promptQuery = _filters.promptQuery.trim();
      final bool aiEntitled =
          widget.canUseVisualMatch && widget.aiVisualService != null;
      // Búsqueda visual (Pro): buscar tu "tipo" es GLOBAL → no restringe por
      // ubicación ni curación de Slow Dating; la IA evalúa a todos los candidatos.
      final bool visualSearch = _filters.sortByVisualReference && aiEntitled;
      // Búsqueda por PROMPT (Pro): descripción en lenguaje natural. Como la
      // visual, es GLOBAL (no restringe por ubicación ni Slow Dating).
      final bool promptSearch = promptQuery.isNotEmpty && aiEntitled;
      _AiSearchState? aiState;
      if (!aiEntitled && _filters.aiSearchActive) {
        aiState = _AiSearchState(
          byPrompt: promptQuery.isNotEmpty,
          status: _AiSearchStatus.notEntitled,
          query: promptQuery,
        );
      }
      // Cualquier búsqueda IA (foto o prompt) desactiva distancia/curación.
      final bool aiSearch = visualSearch || promptSearch;
      // Modo viajes: cuando viajas, el feed se CENTRA en el destino (se ignora
      // la distancia real y se usa el PAÍS de destino para la relevancia).
      final bool traveling = !aiSearch && (widget.user?.isTraveling ?? false);
      // Las coordenadas de esta carga se apuntaron antes del primer await; aquí
      // solo se anulan si el estado cambió por medio (se activó el viaje o una
      // búsqueda IA), porque entonces no se filtra por distancia.
      if (traveling || aiSearch) {
        _loadedLat = null;
        _loadedLng = null;
      }
      final String myCountry = aiSearch
          ? ''
          : (traveling
              ? (widget.user?.travelCountry ?? '')
              : (widget.user?.countryName ?? ''));
      List<SeedProfile> filtered = FeedFilter.apply(
        profiles: all,
        myUid: myUid,
        myGender: widget.user?.gender ?? '',
        myInterestedIn: widget.user?.interestedIn ?? const <String>[],
        excludedUids: excluded,
        filters: _filters,
        // En viaje/búsqueda IA no hay "mi" lat/lng (no filtra por distancia).
        myLat: _loadedLat,
        myLng: _loadedLng,
        myCountry: myCountry,
        defaultMaxKm: aiSearch ? null : widget.user?.maxDistanceKm,
        // Modo Amigos: filtra por compatibilidad de intención (default dating).
        myIntent: widget.user?.intentMode ?? IntentMode.dating,
      );
      // RESPALDO cuando el PAÍS declarado es lo único que vacía el feed.
      //
      // El país sale de `profile.currentCountryName`, que solo se escribe una vez
      // (selector manual del onboarding) porque en la app no hay geocodificación
      // inversa: al cruzar una frontera las coordenadas son las de verdad y el
      // país sigue siendo el de casa, así que la regla de país tira a los de
      // alrededor y la de radio a los del país declarado. Resultado: feed VACÍO,
      // sin explicación y sin salida (el modo viaje es de pago).
      //
      // Solo se aplica cuando el feed se quedaría vacío, así que no relaja la
      // regla "nunca de otro país" para nadie más, y el radio se sigue
      // respetando: lo que entra está SIEMPRE en tu zona.
      bool countryFallback = false;
      if (filtered.isEmpty &&
          !traveling &&
          !aiSearch &&
          !_secondRound &&
          myCountry.isNotEmpty &&
          _loadedLat != null &&
          _loadedLng != null) {
        final List<SeedProfile> nearby = FeedFilter.apply(
          profiles: all,
          myUid: myUid,
          myGender: widget.user?.gender ?? '',
          myInterestedIn: widget.user?.interestedIn ?? const <String>[],
          excludedUids: excluded,
          filters: _filters,
          myLat: _loadedLat,
          myLng: _loadedLng,
          myCountry: '',
          defaultMaxKm: widget.user?.maxDistanceKm,
          myIntent: widget.user?.intentMode ?? IntentMode.dating,
        );
        if (nearby.isNotEmpty) {
          filtered = nearby;
          countryFallback = true;
        }
      }
      if (traveling) {
        filtered = _applyTravel(filtered);
      }
      // Segunda vuelta: quédate SOLO con los perfiles que pasaste.
      if (_secondRound) {
        filtered = filtered
            .where((SeedProfile p) => disliked.contains(p.id))
            .toList(growable: false);
      }
      Map<String, ActiveBoost> activeBoosts = const <String, ActiveBoost>{};
      final BoostService? boostService = widget.boostService;
      if (boostService != null && filtered.isNotEmpty) {
        try {
          activeBoosts = await boostService.fetchActiveBoostsForUsers(
            filtered.map((SeedProfile p) => p.id),
          );
        } catch (_) {
          activeBoosts = const <String, ActiveBoost>{};
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      // Ranking inteligente: si está activo el flag, precarga las señales
      // server-side (prefetch en lote) y construye el inyector signalsFor.
      // Personalización con IA (Datos→consentimiento): si el usuario la
      // desactiva, NO se usan señales personalizadas (orden orgánico neutro).
      final bool useSignals = widget.rankingConfig.enabled &&
          widget.rankingSignals != null &&
          (widget.user?.aiPersonalization ?? true);
      RankingSignals Function(SeedProfile)? signalsFor;
      if (useSignals) {
        try {
          await widget.rankingSignals!
              .prefetch(filtered.map((SeedProfile p) => p.id));
        } catch (_) {/* señales no disponibles: orden orgánico */}
        if (!mounted || generation != _loadGeneration) return;
        signalsFor = (SeedProfile p) => widget.rankingSignals!.signalsFor(p.id);
      }
      // Orden BASE orgánico (compatibilidad real). No salta filtros: solo ordena
      // lo ya filtrado. Los modos opt-in de abajo lo re-curan si están activos.
      filtered = activeBoosts.isEmpty
          ? RankingScorer.rank(
              profiles: filtered,
              me: widget.user,
              signalsFor: signalsFor,
              config: widget.rankingConfig,
            )
          : BoostAwareRanker.rank(
              profiles: filtered,
              me: widget.user,
              activeBoosts: activeBoosts,
              signalsFor: signalsFor,
              config: widget.rankingConfig,
            );
      // Slow Dating (opt-in): cura el feed (menos perfiles, más afines e
      // intencionales). No se aplica en búsqueda visual (que es global).
      // Se le pasan los boosts activos porque, al recortar a sus 12 perfiles
      // por afinidad, borraba por completo el efecto del Boost pagado que
      // BoostAwareRanker acababa de aplicar (ver SlowDatingRanker.maxBoostBonus).
      if (!aiSearch && (widget.user?.slowDatingEnabled ?? false)) {
        filtered = SlowDatingRanker.curate(
          profiles: filtered,
          me: widget.user,
          activeBoosts: activeBoosts,
        );
      }
      // IA visual (Pro): ordena por parecido a la foto de referencia.
      if (visualSearch) {
        final ({List<SeedProfile> profiles, _AiSearchStatus status}) res =
            await _sortByVisualReference(filtered);
        filtered = res.profiles;
        aiState =
            _AiSearchState(byPrompt: false, status: res.status, query: '');
      } else if (promptSearch) {
        // IA por prompt (Pro): deja solo los que encajan con la descripción.
        final ({List<SeedProfile> profiles, _AiSearchStatus status}) res =
            await _sortByPrompt(filtered);
        filtered = res.profiles;
        aiState = _AiSearchState(
            byPrompt: true, status: res.status, query: promptQuery);
      }
      // Plus/Pro: quién te ha dado like -> badge + prioridad al frente del feed.
      Set<String> likedMe = const <String>{};
      if (widget.canSeeLikedMe && myUid.isNotEmpty) {
        try {
          final List<Like> received =
              await widget.matchService.observeReceivedLikes(myUid).first;
          likedMe = received
              .map((Like l) => l.fromUid)
              .where((String id) => id.isNotEmpty)
              .toSet();
        } catch (_) {
          likedMe = const <String>{};
        }
        // Antes se reparticionaba SIEMPRE la lista (todos los "te dio like"
        // al frente). Con una búsqueda IA activa eso reventaba el orden por
        // encaje: el feed decía estar ordenado por parecido/descripción y en
        // realidad mandaba el like. Ahora, con IA, el like solo EMPUJA unas
        // posiciones dentro de ese orden; sin IA se mantiene "al frente".
        filtered = LikedMeRanker.apply(
          profiles: filtered,
          likedMeUids: likedMe,
          nudgePositions: aiSearch ? LikedMeRanker.defaultNudge : null,
        );
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _excluded = excluded;
        _likedMeUids = likedMe;
        _dislikedUids = disliked;
        _activeBoostsByUid = activeBoosts;
        _aiSearch = aiState;
        _countryFallback = countryFallback;
        _rankedPool = filtered;
        _profiles = const <SeedProfile>[];
        _index = 0;
        // Pool nuevo: lo ya decidido vuelve a decidirlo el servidor (`excluded`
        // se acaba de releer), así que la memoria de sesión arranca limpia. Sin
        // esto, la segunda vuelta no podría reponer a quien pasaste.
        _consumed.clear();
        _impressedUid = '';
        _applyStoryWall();
        _pendingAd = false;
        // Pool nuevo: los gestos guardados apuntaban al muro anterior. Se
        // conserva `usedInSession` para no volver a decir "todavía no hay nada
        // que deshacer" a quien ya lo ha usado.
        _rewind = _rewindState.clearHistory();
        _rewinding = false;
        _loading = false;
      });
      // El stream se cae con cualquier error y no se resuscribe solo: "Recargar"
      // tiene que poder revivir el muro, no solo el pool.
      if (_storyWallActive && _storiesSub == null) _bindStories();
      _afterWallChanged();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _error = 'No se pudo cargar el feed. ($error)';
        _loading = false;
      });
    }
  }

  String get _uid => widget.user?.uid ?? '';

  /// Cruza el pool ordenado con quien tiene historias vivas.
  ///
  /// La regla vive en [buildStoryWall] (función pura y testeable). Aquí solo se
  /// le pasa el estado del feed. Con el muro apagado (flag remoto en off o sin
  /// servicio de historias) NO se filtra por historias: Discover se degrada al
  /// feed de perfiles, porque una pantalla vacía para todo el mundo es una
  /// pantalla rota, no una decisión de producto.
  void _applyStoryWall() {
    final StoryWall wall = buildStoryWall(
      rankedPool: _rankedPool,
      storiesByOwner: _storiesByOwner,
      wallActive: _storyWallActive,
      // Bloquear a alguien tiene que sacarlo del muro (Guideline 1.2), y el muro
      // se recompone desde `_rankedPool` en cada snapshot: si el filtro solo
      // estuviera en la suscripción, el bloqueado reaparecía segundos después.
      excludedUids: _excluded,
      consumedUids: _consumed,
      currentUid: (_index >= 0 && _index < _profiles.length)
          ? _profiles[_index].id
          : null,
    );
    _profiles = wall.profiles;
    _index = wall.index;
  }

  /// Un anuncio cada N perfiles vistos (nunca al inicio).
  static const int _adFrequency = 7;
  int _swipesSinceAd = 0;
  bool _pendingAd = false;

  /// Pasa de tarjeta después de un gesto.
  ///
  /// [targetUid] es sobre QUIÉN fue el gesto y se pasa explícito porque no
  /// siempre es la tarjeta actual: con un modal abierto (la hoja de respuesta a
  /// una foto) el muro se recompone por debajo —el stream de historias es
  /// global— y `_profiles[_index]` puede apuntar ya a otra persona. Cogerlo del
  /// índice guardaba el rewind sobre alguien a quien no se le mandó nada y
  /// marcaba como decidida a una persona que el usuario ni había visto.
  void _advance({
    String? targetUid,
    FeedActionKind? rewindAction,
    bool notRewindable = false,
  }) {
    // Tras varios perfiles, inserta una ad card (si procede). No al arrancar.
    _swipesSinceAd++;
    final bool showAd = widget.adsEnabled && _swipesSinceAd >= _adFrequency;
    final String? currentUid = _profileAtIndex()?.id;
    final String? acted = targetUid ?? currentUid;
    setState(() {
      if (acted != null) {
        if (rewindAction != null) {
          // Cuántos se guardan (uno o todos) lo decide el tramo dentro de
          // `record`. Aquí ya no hay ningún `if` de plan: cuando la regla estaba
          // partida entre este método y `_onRewind` no había forma de probarla.
          _rewind = _rewindState
              .record(RewindEntry(targetUid: acted, kind: rewindAction));
        } else if (notRewindable) {
          // Super Attra: el backend se niega a deshacerlo, así que se quita SU
          // entrada (por si esa persona ya estuviera guardada de antes) y solo
          // la suya. Vaciar el historial entero borraba los gestos anteriores,
          // que siguen siendo deshacibles, y encima lo hacía aunque el Attra
          // acabara fallando por saldo.
          _rewind = _rewindState.forget(acted);
        }
        // Decidido (like, pase, Attra o vistas todas sus historias): no puede
        // volver a salir cuando el muro se recomponga.
        _consumed.add(acted);
      }
      if (acted == null || acted == currentUid) {
        _index += 1;
      } else {
        // El gesto era sobre otra persona (el muro cambió con el modal abierto):
        // se recompone el muro para sacarla, pero NO se avanza el índice, que
        // saltaría a quien está delante sin que el usuario haya decidido nada
        // sobre él.
        _applyStoryWall();
      }
      if (showAd) {
        _swipesSinceAd = 0;
        _pendingAd = true;
      }
    });
    _precacheNext();
    _recordCurrentImpression();
  }

  void _removeRewindActionFor(String targetUid) {
    final RewindState next = _rewindState.forget(targetUid);
    if (identical(next, _rewind)) return;
    setState(() => _rewind = next);
  }

  /// Registra como "mostrado" el perfil actualmente visible (impresión).
  void _recordCurrentImpression() {
    if (_uid.isEmpty || _index < 0 || _index >= _profiles.length) return;
    final SeedProfile profile = _profiles[_index];
    // El muro se recompone con cada snapshot del stream global de historias: sin
    // esta guarda, cada uno mandaba otra impresión de Boost (una llamada de red)
    // por la misma persona sin que hubiera cambiado nada en pantalla.
    if (profile.id == _impressedUid) return;
    _impressedUid = profile.id;
    widget.metrics?.recordImpression(_uid, profile.id);
    if (_activeBoostsByUid.containsKey(profile.id)) {
      widget.boostService
          ?.recordBoostImpression(profile.id, feedEventId: 'feed_${profile.id}')
          .catchError((_) {});
    }
  }

  /// Precarga en memoria la foto de la SIGUIENTE tarjeta (y la 2ª de la actual)
  /// para que el swipe sea instantáneo, sin flash de carga. Best-effort.
  void _precacheNext() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final List<String> toWarm = <String>[];
      // Precalienta las DOS siguientes tarjetas (swipe encadenado fluido).
      for (int step = 1; step <= 2; step++) {
        final int n = _index + step;
        if (n >= _profiles.length) break;
        if (_storyWallActive) {
          // En el muro la portada NO es la foto de perfil sino la primera
          // historia: precalentar la foto de perfil calentaría justo lo que no
          // se va a ver (y encima es lo que se oculta a ciegas).
          for (final Story s
              in _storiesByOwner[_profiles[n].id] ?? const <Story>[]) {
            final String url =
                s.previewUrl.isNotEmpty ? s.previewUrl : s.imageUrl;
            if (url.isNotEmpty) toWarm.add(url);
          }
          continue;
        }
        toWarm.add(_profiles[n].primaryPhotoUrl);
        final List<String> g = _profiles[n].galleryUrls;
        if (g.length > 1) toWarm.add(g[1]);
      }
      for (final String url in toWarm) {
        AttraImage.precache(context, url);
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    // Se retira el aviso que hubiera antes de poner el nuevo: los SnackBar se
    // ENCOLAN, y encadenando gestos (deshacer y volver a pulsar) el usuario leía
    // la respuesta del gesto anterior mientras la del suyo esperaba turno cuatro
    // segundos.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tramo vigente, recalculado desde los props en cada lectura (el plan cambia
  /// en caliente).
  RewindTier get _rewindTier => RewindTier.forPlan(
        canRewind: widget.canRewind,
        unlimited: widget.rewindUnlimited,
      );

  /// La marcha atrás con el tramo de AHORA. Es lo que se pinta y lo que se
  /// modifica: nunca se toca `_rewind` directamente.
  RewindState get _rewindState => _rewind.withTier(_rewindTier);

  /// Marcha atrás. La ÚNICA ruta: la usan el botón de la tarjeta del feed y el
  /// del visor a ciegas.
  ///
  /// Antes lo único que ofrecía deshacer era un SnackBar de 4 segundos tras cada
  /// like o pase: si no lo cazabas, no había forma de volver. Y desde el muro de
  /// historias no había ninguna, porque las acciones se toman en el visor.
  Future<void> _onRewind() async {
    if (_rewinding) return;
    // Un like o un pase TODAVÍA EN VUELO no se puede deshacer: `rewindFeedAction`
    // leería el documento antes de que la transacción de `sendLike` lo
    // escribiera, contestaría "no había nada que deshacer" y el like acabaría
    // enviado igualmente. Y arrepentirse en el segundo siguiente es justo la
    // razón de ser de este botón, así que la carrera no es teórica.
    if (_sending > 0) {
      _snack('Tu último gesto todavía está saliendo. Prueba en un segundo.');
      return;
    }
    final RewindState state = _rewindState;
    switch (state.status) {
      case RewindStatus.locked:
        // Free ve el botón a propósito (es el gancho), pero al pulsarlo tiene
        // que entender POR QUÉ no pasa nada y qué le daría cada plan.
        widget.metrics?.log(FeedMetricsService.rewindBlocked,
            uid: _uid,
            targetUid: state.history.isEmpty
                ? null
                : state.history.last.targetUid,
            meta: <String, dynamic>{'tier': _planLabel});
        _snack(state.lockedMessage);
        widget.onOpenUpgrade?.call();
        return;
      case RewindStatus.empty:
        // Sin nada guardado el botón no puede quedarse mudo: parecería roto.
        _snack(state.emptyMessage);
        return;
      case RewindStatus.ready:
        break;
    }

    final RewindEntry action = state.pending!;
    setState(() => _rewinding = true);
    try {
      // Se LEE el bool: el backend distingue "deshecho" de "no había nada que
      // deshacer" (`rewound`) precisamente para esto. Tirarlo hacía que un gesto
      // que nunca llegó a escribirse (tope diario alcanzado, pase que falló y se
      // tragó su error) se cobrara como marcha atrás gastada y encima se
      // anunciara como "Hecho".
      final bool rewound = await widget.matchService.rewindFeedAction(
        targetUid: action.targetUid,
        action: action.kind.wireName,
      );
      if (!mounted) return;
      bool volvio = false;
      setState(() {
        _pendingAd = false;
        _excluded = <String>{..._excluded}..remove(action.targetUid);
        // Deshecha la acción, deja de estar decidido: puede volver a salir.
        // Sin esto el perfil no reaparece y el usuario habría gastado su marcha
        // atrás para nada.
        _consumed.remove(action.targetUid);
        // Se busca por UID, no por la posición guardada: el muro se recompone
        // solo (historias que caducan, bloqueos) y el índice de entonces puede
        // apuntar ya a otra persona.
        int found =
            _profiles.indexWhere((SeedProfile p) => p.id == action.targetUid);
        if (found < 0) {
          // Ya no estaba en el muro. Se recompone AQUÍ, con `_consumed` y
          // `_excluded` recién limpiados: si solo la sacaba una de esas dos
          // listas, vuelve ahora mismo en vez de esperar a un snapshot ajeno o a
          // una recarga (que además borra el historial).
          _applyStoryWall();
          found =
              _profiles.indexWhere((SeedProfile p) => p.id == action.targetUid);
        }
        volvio = found >= 0;
        if (volvio) _index = found;
        // Solo cuenta como marcha atrás GASTADA si el servidor deshizo algo. Si
        // no había nada registrado se olvida el gesto (no era deshacible) pero
        // no se le cobra al usuario su única marcha atrás.
        _rewind = rewound
            ? _rewindState.undoFor(action.targetUid)
            : _rewindState.forget(action.targetUid);
        _rewinding = false;
      });
      if (rewound) {
        // Sin este evento no hay forma de responder a la pregunta que paga la
        // función ("¿se usa la marcha atrás?"), y el embudo se queda con los
        // likeSent/nopeSent de gestos que ya no existen.
        widget.metrics?.log(FeedMetricsService.rewindUsed,
            uid: _uid,
            targetUid: action.targetUid,
            meta: <String, dynamic>{
              'kind': action.kind.wireName,
              'tier': _planLabel,
            });
      }
      if (!rewound) {
        _snack('Ese gesto no llegó a registrarse, así que no te hemos gastado '
            'la marcha atrás.');
      } else if (!volvio) {
        // Se ha deshecho de verdad, pero no hay a quién enseñar: decirlo es la
        // diferencia entre "el botón está roto" y "ya está hecho".
        _snack('Hecho. Ahora mismo no podemos volver a enseñártela; '
            'reaparecerá en cuanto recargues el feed.');
      } else {
        // Se dice lo que queda DESPUÉS de deshacer: es la diferencia entre
        // "puedes seguir" (Pro) y "hasta el siguiente gesto" (Plus).
        _snack(_rewindState.doneMessage);
      }
      _precacheNext();
      _recordCurrentImpression();
    } on MatchServiceException catch (error) {
      _snack(error.message);
      // El gesto solo se OLVIDA cuando el "no" es definitivo (ya hay match, era
      // un Attra, no es tuyo). `_call` envuelve TODAS las
      // FirebaseFunctionsException por igual, así que olvidarlo siempre se comía
      // la única marcha atrás de un Plus por un bache de cobertura —dejando el
      // gesto vivo en el servidor y el botón diciendo "ya no queda nada", que
      // era falso.
      if (mounted && _isPermanentRewindError(error.code)) {
        setState(() => _rewind = _rewindState.forget(action.targetUid));
      }
    } catch (_) {
      // `_call` solo envuelve las FirebaseFunctionsException: un
      // PlatformException del plugin, un timeout o un error de serialización
      // salían crudos, y como el botón invoca esto como VoidCallback el Future
      // se descartaba sin observar. El usuario veía girar el icono y nada más.
      _snack('No hemos podido deshacerlo. Inténtalo otra vez.');
    } finally {
      if (mounted && _rewinding) {
        setState(() => _rewinding = false);
      }
    }
  }

  /// Códigos de `rewindFeedAction` que significan "esto no se va a poder
  /// deshacer NUNCA". El resto (`unavailable`, `deadline-exceeded`, `internal`,
  /// `resource-exhausted`…) son transitorios y el gesto se conserva.
  static bool _isPermanentRewindError(String? code) =>
      code == 'failed-precondition' ||
      code == 'permission-denied' ||
      code == 'invalid-argument';

  String get _planLabel => widget.isPro
      ? 'pro'
      : widget.isPlus
          ? 'plus'
          : 'free';

  /// Attra Clear §2: ¿bloquear este like/Attra por exceso de conversaciones
  /// pendientes? Muestra el bottom sheet (bloqueo SUAVE) y devuelve true si se
  /// debe abortar la acción. Nunca bloquea acciones de seguridad ni en modo
  /// ocupado, y solo si el flag está activo.
  Future<bool> _pendingBlocks({required bool isAttra}) async {
    final AntiGhostingConfig? cfg = widget.antiGhostingConfig;
    final PendingConversationsController? pc = widget.pendingController;
    if (cfg == null || pc == null || !cfg.enabled || !cfg.pendingLimitEnabled) {
      return false;
    }
    if (widget.isBusy) return false; // §12: no penaliza en modo ocupado
    final bool softBlock = isAttra
        ? cfg.softBlockAttrasWhenPendingExceeded
        : cfg.softBlockLikesWhenPendingExceeded;
    if (!softBlock) return false;
    final int limit =
        cfg.pendingLimitForPlan(isPlus: widget.isPlus, isPro: widget.isPro);
    final int count = pc.pendingCount(cfg.pendingMaxAgeHours);
    if (count < limit) return false;

    final AntiGhostingAnalytics analytics =
        AntiGhostingAnalytics(uid: _uid, metrics: widget.metrics);
    analytics.logPendingLimitReached(pendingCount: count, userPlan: _planLabel);
    if (!mounted) return true;
    final PendingLimitAction? action =
        await PendingLimitBottomSheet.show(context, pendingCount: count);
    if (action != null && action != PendingLimitAction.notNow) {
      analytics.logPendingLimitCta(
          action: action.name, pendingCount: count, userPlan: _planLabel);
      if (action == PendingLimitAction.viewConversations ||
          action == PendingLimitAction.closeSome) {
        widget.onOpenChats?.call();
      }
    }
    return true; // bloqueado: no se envía el like/Attra
  }

  Future<void> _onLikeProfile(SeedProfile profile) async {
    widget.metrics
        ?.log(FeedMetricsService.likeSent, uid: _uid, targetUid: profile.id);
    // Sin SnackBar de "Like enviado / Deshacer": era la ÚNICA forma de volver
    // atrás y duraba 4 segundos. Ahora deshacer es un botón permanente (en la
    // tarjeta y en el visor a ciegas), así que el aviso fugaz solo tapaba la
    // barra de acciones del visor.
    _advance(targetUid: profile.id, rewindAction: FeedActionKind.like);
    await _sendAndHandle(
        () => widget.matchService.sendLike(profile.id), profile);
  }

  Future<void> _onPass(SeedProfile profile) async {
    widget.metrics
        ?.log(FeedMetricsService.nopeSent, uid: _uid, targetUid: profile.id);
    _advance(targetUid: profile.id, rewindAction: FeedActionKind.pass);
    _markSending(1);
    try {
      await widget.matchService.passProfile(profile.id);
    } catch (_) {
      // Descartar es best-effort: el gesto SE QUEDA en el historial aunque
      // falle. Deshacerlo entonces no encuentra dislike, el backend contesta
      // `rewound: false` y `_onRewind` repone a la persona sin cobrar la marcha
      // atrás, que es exactamente lo que el usuario quiere en ese caso.
    } finally {
      _markSending(-1);
    }
  }

  /// Super Attra desde el muro a ciegas.
  ///
  /// Es la MISMA acción que el Attra de la tarjeta de perfil: mismo gate de
  /// pendientes, mismo saldo, mismo evento `attraSent`, mismo `sendAttra` y el
  /// mismo borrado del historial de rewind (un Attra no se deshace). Lo único
  /// que no lleva es `targetPhotoId`/comentario: a ciegas no hay una foto del
  /// perfil que señalar, y mandar el id de una historia como si fuera una foto
  /// de perfil dejaría likes apuntando a media que caduca en 72 h.
  Future<void> _onSuperAttra(SeedProfile profile) async {
    if (await _pendingBlocks(isAttra: true)) return;
    if (!mounted) return;
    if (widget.attrasBalance <= 0) {
      _snack('No tienes Attras suficientes.');
      return;
    }
    widget.metrics
        ?.log(FeedMetricsService.attraSent, uid: _uid, targetUid: profile.id);
    _advance(targetUid: profile.id, notRewindable: true);
    await _sendAndHandle(
        () => widget.matchService.sendAttra(profile.id), profile);
  }

  Future<void> _onRespondToPhoto(
    SeedProfile profile,
    AdditionalPhoto photo,
    PhotoResponseKind kind,
  ) async {
    if (await _pendingBlocks(isAttra: kind == PhotoResponseKind.attra)) {
      return;
    }
    if (!mounted) return;
    if (kind == PhotoResponseKind.attra && widget.attrasBalance <= 0) {
      _snack('No tienes Attras suficientes.');
      return;
    }
    final PhotoResponseResult? res = await PhotoResponseSheet.show(
      context,
      kind: kind,
      name: profile.displayName,
      photoUrl: photo.url,
      attraBalance: widget.attrasBalance,
      canComment: widget.canComment,
    );
    if (res == null || !mounted) return;
    final String? photoId = photo.storagePath.isNotEmpty
        ? photo.storagePath
        : photo.url.isNotEmpty
            ? photo.url
            : null;
    if (res.kind == PhotoResponseKind.like) {
      widget.metrics
          ?.log(FeedMetricsService.likeSent, uid: _uid, targetUid: profile.id);
      _advance(targetUid: profile.id, rewindAction: FeedActionKind.like);
      await _sendAndHandle(
        () => widget.matchService
            .sendLike(profile.id, targetPhotoId: photoId, comment: res.comment),
        profile,
      );
    } else {
      widget.metrics
          ?.log(FeedMetricsService.attraSent, uid: _uid, targetUid: profile.id);
      _advance(targetUid: profile.id, notRewindable: true);
      await _sendAndHandle(
        () => widget.matchService.sendAttra(profile.id,
            targetPhotoId: photoId, comment: res.comment),
        profile,
      );
    }
  }

  Future<void> _onRespondToPrompt(
      SeedProfile profile, PublicPrompt prompt) async {
    final PhotoResponseResult? res = await PromptResponseSheet.show(
      context,
      name: profile.displayName,
      question: prompt.question,
      answer: prompt.answer,
      attraBalance: widget.attrasBalance,
      canComment: widget.canComment,
    );
    if (res == null || !mounted) return;
    if (res.kind == PhotoResponseKind.like) {
      await _sendAndHandle(
        () => widget.matchService.sendLike(
          profile.id,
          promptId: prompt.id,
          promptQuestion: prompt.question,
          promptAnswer: prompt.answer,
          comment: res.comment,
        ),
        profile,
      );
    } else {
      await _sendAndHandle(
        () => widget.matchService.sendAttra(
          profile.id,
          promptId: prompt.id,
          promptQuestion: prompt.question,
          promptAnswer: prompt.answer,
          comment: res.comment,
        ),
        profile,
      );
    }
  }

  /// Intereses en común con [profile] (case-insensitive, conserva el texto del
  /// otro perfil). Para la pantalla de match.
  List<String> _sharedInterestsWith(SeedProfile profile) {
    final Set<String> mine = <String>{
      for (final String i in widget.user?.interests ?? const <String>[])
        i.trim().toLowerCase()
    }..removeWhere((String s) => s.isEmpty);
    if (mine.isEmpty) return const <String>[];
    return profile.interests
        .where((String i) => mine.contains(i.trim().toLowerCase()))
        .take(4)
        .toList(growable: false);
  }

  /// Gestos EN VUELO (like/Attra/pase que el backend todavía no ha confirmado).
  ///
  /// Es un contador y no un bool porque el visor a ciegas y la tarjeta pueden
  /// encadenar gestos antes de que el anterior conteste. Mientras haya alguno,
  /// la marcha atrás espera: deshacer un like que aún no se ha escrito es un
  /// no-op que además deja el like enviado.
  int _sending = 0;

  void _markSending(int delta) {
    _sending += delta;
    if (mounted) setState(() {});
  }

  Future<void> _sendAndHandle(
      Future<MatchFlowResult> Function() call, SeedProfile profile) async {
    final MatchFlowResult result;
    _markSending(1);
    try {
      result = await call();
    } on MatchServiceException catch (error) {
      _snack(error.message);
      return;
    } finally {
      // Se suelta ANTES de los diálogos (match, revelado): son del usuario, no
      // de la red, y mantener el botón en espera mientras están abiertos lo
      // dejaría bloqueado minutos.
      _markSending(-1);
    }
    if (!mounted) return;
    try {
      switch (result.outcome) {
        case MatchOutcome.matched:
          _removeRewindActionFor(profile.id);
          widget.metrics?.log(FeedMetricsService.matchCreated,
              uid: _uid, targetUid: profile.id);
          final String matchChatId = result.chatId ?? '';
          await showMatchCreatedDialog(
            context,
            name: profile.displayName,
            photoUrl: profile.primaryPhotoUrl,
            hasAttra: false,
            currentUserPhotoUrl: widget.user?.photoUrl,
            sharedInterests: _sharedInterestsWith(profile),
            originComment: result.message,
            onOpenChat: () => _openChat(matchChatId, profile),
            onSendFirstMessage: matchChatId.isEmpty
                ? null
                : (String text) => widget.chatService
                    .sendMessage(chatId: matchChatId, text: text),
            onPlaySpark: (widget.sparkEnabled &&
                    widget.sparkService != null &&
                    matchChatId.isNotEmpty)
                ? () => _playSpark(matchChatId, profile)
                : null,
          );
          // La recompensa del muro a ciegas: hasta aquí solo se han visto
          // nombre, edad e historias. Solo se revela cuando el match viene del
          // muro; en el feed de perfiles ya se había visto todo y este paso
          // sobraría.
          if (_storyWallActive && mounted) {
            await _revealProfile(profile);
          }
          break;
        case MatchOutcome.limitReached:
          _snack('Has alcanzado tu límite de likes de hoy.');
          break;
        case MatchOutcome.insufficientAttras:
          _snack('No tienes Attras suficientes.');
          break;
        case MatchOutcome.blocked:
          _snack('No puedes interactuar con este perfil.');
          break;
        case MatchOutcome.liked:
        case MatchOutcome.error:
          break;
        case MatchOutcome.alreadyLiked:
          _removeRewindActionFor(profile.id);
          break;
      }
    } on MatchServiceException catch (error) {
      _snack(error.message);
    }
  }

  /// Revela el perfil completo tras un match nacido en el muro a ciegas.
  Future<void> _revealProfile(SeedProfile profile) async {
    await ProfileRevealScreen.show(
      context,
      name: profile.displayName,
      age: profile.age,
      photoUrl: profile.primaryPhotoUrl,
      onOpenProfile: () {
        // Se cierra la pantalla de revelado antes de abrir el perfil: si no,
        // volver del perfil te devolvía al revelado, que ya no pinta nada.
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProfileViewScreen(
            profile: profile,
            matchService: widget.matchService,
          ),
        ));
      },
    );
  }

  /// Attra Spark (juego de 5 min) recién creado el match.
  Future<void> _playSpark(String matchId, SeedProfile profile) async {
    final SparkService? spark = widget.sparkService;
    if (spark == null || matchId.isEmpty) return;
    try {
      final String sessionId = await spark.invite(
        matchId: matchId,
        hostUid: _uid,
        guestUid: profile.id,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SparkGameScreen(
          service: spark,
          matchId: matchId,
          sessionId: sessionId,
          currentUid: _uid,
          otherName: profile.displayName,
          onOpenChat: () => _openChat(matchId, profile),
        ),
      ));
    } on Exception {
      if (mounted) _snack('No se pudo iniciar el juego.');
    }
  }

  void _openChat(String chatId, SeedProfile profile) {
    if (chatId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatDetailScreen(
        onOpenUpgrade: widget.onOpenUpgrade,
        chatId: chatId,
        currentUid: widget.user?.uid ?? '',
        other: ProfileSummary(
          uid: profile.id,
          displayName: profile.displayName,
          photoUrl: profile.primaryPhotoUrl,
        ),
        chatService: widget.chatService,
        matchService: widget.matchService,
        metrics: widget.metrics,
      ),
    ));
  }

  Future<void> _openFilters() async {
    final FeedFilters? result = await FiltersScreen.show(
      context,
      initial: _filters,
      isPlus: widget.isPlus,
      canVisualMatch: widget.canUseVisualMatch,
    );
    if (result == null || !mounted) return;
    setState(() => _filters = result);
    _load();
  }

  Widget _feedHeader() {
    final Widget filterButton = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          IconButton(
            tooltip: 'Filtros',
            icon: const Icon(Icons.tune),
            onPressed: _openFilters,
          ),
          if (_filters.activeCount > 0)
            Positioned(
              right: 4,
              top: 4,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  '${_filters.activeCount}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // Botón de Modo viajes (globo). Se resalta si estás de viaje.
    final bool traveling = widget.user?.isTraveling ?? false;
    final Widget travelButton = IconButton(
      tooltip: 'Modo viajes',
      icon: Icon(
        traveling ? Icons.travel_explore_rounded : Icons.public_rounded,
        color: traveling ? AppColors.attraRed : null,
      ),
      onPressed: widget.onOpenTravel,
    );
    // La tira de aros ya no vive aquí: el MURO es Discover, así que una fila de
    // aros encima del muro era el mismo contenido dos veces. Lo que SÍ tiene que
    // seguir estando es la forma de publicar: la tira era el único sitio desde
    // el que se abría el editor de historias y, sin él, un muro que solo enseña
    // a quien tiene historia viva se vacía solo en 72 h.
    final String uid = widget.user?.uid ?? '';
    final StoryService? storyService = widget.storyService;
    final Widget? myStoryButton =
        (_storiesEnabled && storyService != null && uid.isNotEmpty)
            ? MyStoryButton(currentUid: uid, storyService: storyService)
            : null;
    return SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                _storyWallActive ? 'A ciegas' : 'Descubrir',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          if (myStoryButton != null) myStoryButton,
          travelButton,
          filterButton,
        ],
      ),
    );
  }

  /// Aviso de ubicación. Explica QUÉ pasa y ofrece la acción que lo arregla:
  /// sin él, quien tenía el permiso denegado (o una ubicación de hace meses) veía
  /// un feed de otra ciudad sin ninguna pista de por qué.
  Widget _locationBanner() {
    final String message;
    final String action;
    final IconData icon;
    switch (_locationNotice) {
      case LocationNotice.permissionAskable:
        // No dice "te enseñamos gente de tu país, no de tu zona": eso solo es
        // verdad si NO hay coordenadas guardadas, y este aviso también sale con
        // coordenadas buenas (en iOS, "Permitir una vez" vuelve como
        // notDetermined en el arranque siguiente). Afirmar algo falso para
        // mendigar un permiso es peor que no avisar.
        message = 'Sin permiso de ubicación no podemos mantener tu zona al día';
        action = 'Activar';
        icon = Icons.location_off_rounded;
        break;
      case LocationNotice.permissionBlocked:
        message = 'La ubicación está bloqueada para Attra';
        action = 'Ajustes';
        icon = Icons.location_disabled_rounded;
        break;
      case LocationNotice.serviceDisabled:
        // En iOS el botón NO puede llevar al interruptor global: el plugin mapea
        // `openLocationSettings` y `openAppSettings` al MISMO destino (los
        // ajustes de Attra), donde ese interruptor no está. Se dice la ruta en
        // vez de prometer un atajo que no existe.
        message = defaultTargetPlatform == TargetPlatform.iOS
            ? 'Ubicación apagada: Ajustes › Privacidad y seguridad › Localización'
            : 'La ubicación del dispositivo está apagada';
        action = 'Ajustes';
        icon = Icons.location_disabled_rounded;
        break;
      case LocationNotice.stale:
        message = 'Tu ubicación puede estar desactualizada';
        action = 'Actualizar';
        icon = Icons.my_location_rounded;
        break;
      case LocationNotice.none:
        return const SizedBox.shrink();
    }
    return Material(
      color: AppColors.attraRed.withValues(alpha: 0.12),
      child: InkWell(
        onTap: _locationRefreshing ? null : _onLocationNoticeTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: AppColors.attraRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: AppColors.attraRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              if (_locationRefreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.attraRed),
                )
              else
                Text(action,
                    style: const TextStyle(
                        color: AppColors.attraRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// Aviso de que el feed ha tenido que ignorar el país declarado para no
  /// quedarse vacío. Sin explicación, ver perfiles de otro país parece un error
  /// (y un feed vacío, un feed roto).
  Widget _countryFallbackBanner() {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.outline;
    final String country = (widget.user?.countryName ?? '').trim();
    return Material(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.travel_explore_rounded, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                country.isEmpty
                    ? 'No hay nadie de tu país en tu zona: te enseñamos gente de alrededor'
                    : 'No hay nadie de $country en tu zona: te enseñamos gente de alrededor',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner cuando estás de viaje: indica el destino y permite volver.
  Widget _travelBanner() {
    final String label = widget.user?.travelLabel ?? '';
    return Material(
      color: AppColors.attraRed.withValues(alpha: 0.12),
      child: InkWell(
        onTap: widget.onOpenTravel,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.flight_takeoff_rounded,
                  size: 16, color: AppColors.attraRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.isEmpty ? 'Estás de viaje' : 'De viaje en $label',
                  style: const TextStyle(
                      color: AppColors.attraRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              const Text('Cambiar',
                  style: TextStyle(
                      color: AppColors.attraRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// Quita las búsquedas IA (foto de referencia + descripción) y recarga. Es la
  /// salida que antes no existía: con el filtro IA puesto el feed se quedaba en
  /// blanco y no había forma de desactivarlo desde el propio feed.
  void _clearAiSearch() {
    setState(() {
      _filters =
          _filters.copyWith(sortByVisualReference: false, promptQuery: '');
      _aiSearch = null;
    });
    _load();
  }

  /// Banner permanente cuando hay una búsqueda IA pedida: dice QUÉ filtro está
  /// activo (o que no se está aplicando) y permite quitarlo de un toque.
  Widget _aiSearchBanner(_AiSearchState ai) {
    final ThemeData theme = Theme.of(context);
    final bool inactive = ai.status == _AiSearchStatus.notEntitled;
    final Color color =
        inactive ? theme.colorScheme.outline : theme.colorScheme.primary;
    final String text = inactive
        ? 'Filtro IA guardado (${ai.label}): no se aplica, es de Attra Pro'
        : 'Búsqueda IA activa: ${ai.label}';
    return Material(
      color: color.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _clearAiSearch,
              child: const Text('Quitar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Estado vacío cuando la causa es la búsqueda IA: explica el motivo real
  /// (nadie encaja / motor caído / error) y ofrece quitar el filtro.
  Widget _aiEmptyState(_AiSearchState ai) {
    final bool byPrompt = ai.byPrompt;
    final String what =
        byPrompt ? 'tu descripción (${ai.label})' : 'tu foto de referencia';
    final String message;
    switch (ai.status) {
      case _AiSearchStatus.noMatches:
        message = byPrompt
            ? 'Ninguno de los perfiles disponibles encaja con $what. Prueba con una descripción menos específica o quita el filtro para ver el feed completo.'
            : 'Ninguno de los perfiles disponibles se parece lo suficiente a $what. Quita el filtro para ver el feed completo.';
        break;
      case _AiSearchStatus.unavailable:
        message =
            'La búsqueda IA no está disponible ahora mismo, así que no ha podido devolver resultados. Tu feed está vacío por este filtro, no porque no haya gente.';
        break;
      case _AiSearchStatus.failed:
        message =
            'La búsqueda IA ha fallado (puede ser la conexión). Tu feed está vacío por este filtro, no porque no haya gente.';
        break;
      case _AiSearchStatus.ok:
      case _AiSearchStatus.notEntitled:
        message =
            'Tienes una búsqueda IA activa filtrando el feed. Quítala para ver el resto de perfiles.';
        break;
    }
    return _FeedEndState(
      icon: Icons.filter_alt_off_rounded,
      title: 'El filtro IA ha dejado el feed vacío',
      message: message,
      primaryLabel: 'Quitar el filtro IA',
      onPrimary: _clearAiSearch,
      secondaryLabel: 'Reintentar',
      onSecondary: _load,
    );
  }

  /// Muestra el acceso a grupos en el feed cuando el usuario está en un modo
  /// social (amistad / ambas / planes en grupo). En modo grupos el feed de
  /// personas queda vacío, así que este acceso es la vía a los grupos.
  bool get _showGroupsBanner {
    if (widget.onOpenGroups == null) return false;
    final IntentMode mode = widget.user?.intentMode ?? IntentMode.dating;
    return mode.isSocial || mode.isBoth;
  }

  Widget _groupsBanner() {
    final ThemeData theme = Theme.of(context);
    final bool groupsMode = widget.user?.intentMode.isGroups ?? false;
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: 0.10),
      child: InkWell(
        onTap: widget.onOpenGroups,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.groups_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  groupsMode
                      ? 'Estás en modo Planes en grupo. Descubre grupos aquí'
                      : 'Grupos y planes por intereses',
                  style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _AiSearchState? ai = _aiSearch;
    // El visor a ciegas es una vista del estado del feed, no un estado aparte:
    // se resincroniza en cada frame para que like, pase, rewind, bloqueo,
    // historia caducada y anuncio le lleguen sin rutas paralelas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBlindWall();
    });
    return Column(
      children: <Widget>[
        _feedHeader(),
        if (widget.user?.isTraveling ?? false) _travelBanner(),
        // Va después del de viaje porque viajando no se enseña (la política
        // devuelve `none`): el feed del destino es intencionado, no un fallo.
        if (_locationNotice != LocationNotice.none) _locationBanner(),
        if (_countryFallback) _countryFallbackBanner(),
        // Aviso siempre visible del filtro IA: sin él, el usuario no tenía
        // ninguna pista de que una búsqueda IA le estaba recortando el feed.
        if (ai != null) _aiSearchBanner(ai),
        if (_showGroupsBanner) _groupsBanner(),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    // Con el muro activo, el pool no vale de nada hasta que llegan las
    // historias: pintarlo antes enseñaría un instante el feed de PERFILES, que
    // es justo lo que el "a ciegas" evita. Mientras el flag remoto no ha
    // contestado tampoco se puede pintar: `_storyWallActive` es false hasta
    // entonces, así que si el pool ganaba la carrera se enseñaba la ficha
    // completa (bio, trabajo, estudios, altura, verificación, distancia).
    if (_loading ||
        !_storiesFlagResolved ||
        (_storyWallActive && !_storiesLoaded)) {
      return const AttraProfileCardSkeleton();
    }
    if (_error != null) {
      return AttraEmptyState(
        icon: Icons.error_outline,
        title: 'Algo salió mal',
        message: _error!,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    // Sin perfiles disponibles O ya vistos todos: mismo estado permanente. NO
    // se reinicia el indice (los perfiles vistos no deben reaparecer); solo
    // "Recargar" vuelve a consultar y re-excluye lo ya likeado/pasado/matcheado.
    if (_profiles.isEmpty || _index >= _profiles.length) {
      final Widget empty = _exhaustedContent(context);
      // El feed se acaba justo DESPUÉS de un gesto, así que aquí es donde más
      // falta hace poder deshacerlo... y es justo donde ya no hay tarjeta que
      // lleve el botón. Además "Recargar" borra el historial (el pool es otro),
      // o sea que sin esto la última marcha atrás se perdía sin usarse.
      //
      // Free NO puede deshacer, pero SÍ guarda el gesto, y esta es la pantalla
      // donde más tiempo pasa: la franja sale también bloqueada (lleva al
      // paywall) siempre que haya un gesto real detrás. Lo que se oculta es el
      // estado vacío, que solo podría decir "no queda nada" y sería ruido.
      final RewindState rewind = _rewindState;
      final bool hayGesto = rewind.canUndo ||
          (rewind.status == RewindStatus.locked && rewind.history.isNotEmpty);
      if (!hayGesto) return empty;
      return Column(
        children: <Widget>[
          Expanded(child: empty),
          SafeArea(top: false, child: _rewindStrip()),
        ],
      );
    }

    // Ad card nativa intercalada (cada N perfiles, solo si adsEnabled).
    if (_pendingAd) {
      return SafeArea(
        child: FeedNativeAdCard(
          onContinue: () {
            if (mounted) setState(() => _pendingAd = false);
          },
        ),
      );
    }

    final SeedProfile profile = _profiles[_index];
    final bool likedMe = _likedMeUids.contains(profile.id);
    // En el muro la tarjeta es la PILA de historias de esa persona; fuera del
    // muro (flag apagado) sigue siendo la tarjeta de perfil de siempre.
    final List<Story> stories = _storyWallActive
        ? (_storiesByOwner[profile.id] ?? const <Story>[])
        : const <Story>[];
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: likedMe
            ? const EdgeInsets.fromLTRB(4, 4, 4, 4)
            : const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: _SwipeCard(
          key: const ValueKey<String>('feed-swipe-card'),
          profile: profile,
          likedMe: likedMe,
          stories: stories,
          storySeen: _ownerStoriesSeen(profile.id),
          onOpenStory: _openBlindViewer,
          // Marcha atrás en la propia tarjeta: es donde se da el like y el pase
          // cuando el muro está apagado.
          rewind: _rewindState,
          rewinding: _rewinding,
          // Con un gesto en vuelo el botón espera (no gira): deshacer antes de
          // que el like esté escrito lo dejaría enviado para siempre.
          pendingSend: _sending > 0,
          onRewind: _onRewind,
          onBeforeLike: () async => !await _pendingBlocks(isAttra: false),
          onLike: () => _onLikeProfile(profile),
          onPass: () => _onPass(profile),
          onRespondToPhoto: (
            AdditionalPhoto photo,
            PhotoResponseKind kind,
          ) =>
              _onRespondToPhoto(profile, photo, kind),
          onRespondToPrompt: (PublicPrompt prompt) =>
              _onRespondToPrompt(profile, prompt),
          onSafetyMenu: () => _openSafetyMenu(profile),
        ),
      ),
    );
  }

  /// Franja de marcha atrás para cuando NO hay tarjeta (feed agotado).
  ///
  /// Solo sale si hay un gesto guardado detrás (lo decide quien la pinta): en el
  /// estado vacío un botón que solo sirve para decir "no queda nada" es ruido.
  Widget _rewindStrip() {
    final RewindState state = _rewindState;
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: OutlinedButton.icon(
        key: const ValueKey<String>('feed-rewind-strip'),
        onPressed: (_rewinding || _sending > 0) ? null : _onRewind,
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: Text(state.hint),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// Estado permanente de "no hay (más) perfiles". Sale de [_buildContent] para
  /// poder colgarle debajo la marcha atrás sin repetir sus seis ramas.
  Widget _exhaustedContent(BuildContext context) {
    // El stream de historias se cayó antes de traer nada: el muro no está
    // vacío, es que no se ha podido leer. Va lo PRIMERO porque cualquier otro
    // mensaje de aquí (filtro IA, "nadie está contando nada") culparía a quien
    // no es y encima ofrecía un botón que no arreglaba nada.
    if (_storyWallActive && _storiesUnavailable && _storiesByOwner.isEmpty) {
      return AttraEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No hemos podido cargar las historias',
        message:
            'Puede ser la conexión. Lo reintentamos solos cada pocos segundos; si tienes prisa, prueba tú.',
        actionLabel: 'Reintentar',
        onAction: _reloadWall,
      );
    }
    // Feed vacío CON búsqueda IA aplicada: la causa es el filtro, no la falta
    // de gente. Se explica y se ofrece quitarlo (antes: mensaje genérico).
    final _AiSearchState? ai = _aiSearch;
    // (Con `ok` o `notEntitled` la IA no es la culpable: el feed venía vacío
    // de los filtros previos o el filtro ni se aplicó → mensaje genérico.)
    if (ai != null &&
        _profiles.isEmpty &&
        ai.status != _AiSearchStatus.ok &&
        ai.status != _AiSearchStatus.notEntitled) {
      return _aiEmptyState(ai);
    }
    // Fin de la segunda vuelta: se acabaron los perfiles que pasaste.
    if (_secondRound) {
      return AttraEmptyState(
        icon: Icons.refresh_rounded,
        title: 'Fin de la segunda vuelta',
        message:
            'Ya has revisado a quienes pasaste. Vuelve al feed normal para descubrir gente nueva.',
        actionLabel: 'Volver al feed',
        onAction: _exitSecondRound,
      );
    }
    // Muro vacío HABIENDO gente compatible: la causa no es que no haya
    // perfiles, es que nadie ha publicado. Decirlo evita que el usuario crea
    // que sus filtros están mal puestos.
    if (_storyWallActive && _rankedPool.isNotEmpty) {
      const String wallMessage =
          'Aquí solo aparece quien tiene una historia viva: se descubre a la gente por lo que cuenta, no por su ficha. Las historias duran 72 h, así que vuelve en un rato.';
      // La segunda vuelta sigue existiendo en el muro: a quien pasaste puede
      // haberle caducado la historia que viste y haber publicado otra.
      if (_dislikedUids.isNotEmpty) {
        return _FeedEndState(
          icon: Icons.auto_stories_outlined,
          title: 'Nadie está contando nada ahora mismo',
          message: wallMessage,
          primaryLabel: 'Recargar',
          onPrimary: _reloadWall,
          secondaryLabel: 'Dar una segunda vuelta',
          onSecondary: _enterSecondRound,
        );
      }
      return AttraEmptyState(
        icon: Icons.auto_stories_outlined,
        title: 'Nadie está contando nada ahora mismo',
        message: wallMessage,
        actionLabel: 'Recargar',
        onAction: _reloadWall,
      );
    }
    // Feed vacío con pases guardados: ofrece la segunda vuelta.
    if (_dislikedUids.isNotEmpty) {
      return _FeedEndState(
        icon: Icons.replay_rounded,
        title: 'Se acabó el feed por ahora',
        message:
            '¿Quieres dar una segunda vuelta? Puedes volver a ver a las ${_dislikedUids.length} personas que pasaste, por si les das otra oportunidad.',
        primaryLabel: 'Dar una segunda vuelta',
        onPrimary: _enterSecondRound,
        secondaryLabel: 'Recargar',
        onSecondary: _reloadFeed,
      );
    }
    return AttraEmptyState(
      icon: Icons.search_off,
      title: 'No hay más personas por el momento',
      message:
          'Cuando entren nuevos perfiles compatibles aparecerán aquí. No volverás a ver a quien ya likeaste o pasaste.',
      actionLabel: 'Recargar',
      onAction: _reloadFeed,
    );
  }

  /// Guideline 1.2: reportar contenido objetable y bloquear usuarios abusivos
  /// desde el propio feed, sin necesidad de match ni de chat previo.
  Future<void> _openSafetyMenu(SeedProfile profile) async {
    final SafetyActionResult result = await SafetyActions.showSheet(
      context,
      matchService: widget.matchService,
      uid: profile.id,
      displayName: profile.displayName,
    );
    if (!mounted || result != SafetyActionResult.blocked) return;
    // Bloqueado: fuera del feed inmediatamente. No basta con sacarlo de
    // `_profiles`: el muro se recompone desde `_rankedPool` en cada snapshot de
    // historias —basta con que el propio usuario vea la siguiente, que
    // incrementa `viewsCount`— y el bloqueado volvía a aparecer segundos
    // después. Se reconstruyen las listas en vez de mutarlas porque pueden ser
    // no modificables.
    setState(() {
      _excluded = <String>{..._excluded, profile.id};
      _consumed.add(profile.id);
      _rankedPool = _rankedPool
          .where((SeedProfile p) => p.id != profile.id)
          .toList(growable: false);
      _applyStoryWall();
    });
    _afterWallChanged();
  }
}

class _SwipeCard extends StatefulWidget {
  const _SwipeCard({
    super.key,
    required this.profile,
    required this.onBeforeLike,
    required this.onLike,
    required this.onPass,
    required this.onRespondToPhoto,
    required this.onRespondToPrompt,
    required this.onSafetyMenu,
    required this.rewind,
    required this.onRewind,
    this.rewinding = false,
    this.pendingSend = false,
    this.likedMe = false,
    this.stories = const <Story>[],
    this.storySeen = false,
    this.onOpenStory,
  });

  final SeedProfile profile;
  final bool likedMe;

  /// Marcha atrás: estado (calculado por el feed) y acción. La tarjeta no sabe
  /// de planes ni de historial, solo lo pinta.
  final RewindState rewind;

  /// Hay una marcha atrás EN CURSO: el botón gira y la tarjeta deja de aceptar
  /// deslizamientos. Sin ese bloqueo, un swipe a mitad de la llamada guardaba un
  /// gesto nuevo que la respuesta del rewind descartaba en su lugar.
  final bool rewinding;

  /// Hay un like/pase saliendo todavía: el botón espera, sin girar.
  final bool pendingSend;
  final VoidCallback onRewind;

  /// Historias vivas de esta persona. Si NO está vacío, la tarjeta es la pila a
  /// ciegas del muro; si está vacío, la tarjeta de perfil de siempre (que es lo
  /// que se ve con el flag `storiesEnabled` apagado).
  final List<Story> stories;
  final bool storySeen;
  final VoidCallback? onOpenStory;

  /// Guideline 1.2: abre Reportar / Bloquear para el perfil de la tarjeta.
  final VoidCallback onSafetyMenu;
  final Future<bool> Function() onBeforeLike;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final void Function(AdditionalPhoto photo, PhotoResponseKind kind)
      onRespondToPhoto;
  final void Function(PublicPrompt prompt) onRespondToPrompt;

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 100;

  late final AnimationController _controller;
  Animation<double>? _animation;
  double _dx = 0;
  double _cardWidth = 360;
  bool _checkingLike = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        final Animation<double>? anim = _animation;
        if (anim != null) {
          setState(() => _dx = anim.value);
        }
      });
  }

  @override
  void didUpdateWidget(covariant _SwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _controller.stop();
      setState(() => _dx = 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runTo(double target, {VoidCallback? onDone}) {
    _animation = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller
      ..reset()
      ..forward().whenCompleteOrCancel(() {
        if (onDone != null) {
          onDone();
        }
      });
  }

  void triggerSwipe(bool like) {
    _runTo(like ? _cardWidth * 1.6 : -_cardWidth * 1.6,
        onDone: like ? widget.onLike : widget.onPass);
  }

  Future<void> _trySwipe(bool like) async {
    if (!like) {
      triggerSwipe(false);
      return;
    }
    if (_checkingLike) return;
    _checkingLike = true;
    final bool allowed = await widget.onBeforeLike();
    if (!mounted) return;
    _checkingLike = false;
    if (allowed) {
      triggerSwipe(true);
    } else {
      _runTo(0);
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Mientras se deshace un gesto la tarjeta no acepta otro: la marcha atrás
    // está a punto de recolocar el muro y el like caería sobre quien no es.
    if (_checkingLike || widget.rewinding) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (widget.rewinding) {
      _runTo(0);
      return;
    }
    if (_dx.abs() > _threshold) {
      unawaited(_trySwipe(_dx > 0));
    } else {
      _runTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _cardWidth = constraints.maxWidth;
        final double angle = (_dx / _cardWidth) * 0.25;
        final double likeOpacity = (_dx / _threshold).clamp(0.0, 1.0);
        final double nopeOpacity = (-_dx / _threshold).clamp(0.0, 1.0);

        // El cuerpo de la tarjeta: la PILA de historias en el muro, o el perfil
        // completo cuando el muro no está activo. El resto de la tarjeta (swipe,
        // sellos, botón de seguridad) es idéntico en ambos casos: así una misma
        // acción no se comporta distinto según lo que se esté viendo.
        final Widget body = widget.stories.isNotEmpty
            ? StoryStackCard(
                stories: widget.stories,
                displayName: widget.profile.displayName,
                age: widget.profile.age,
                likedMe: widget.likedMe,
                allSeen: widget.storySeen,
                onTap: widget.onOpenStory ?? () {},
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  // Realce editorial para quien te dio like: borde limpio, sin
                  // convertir una señal relacional en una alerta roja.
                  border: widget.likedMe
                      ? Border.all(color: context.colors.accent, width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: _ProfileDetail(
                      profile: widget.profile,
                      likedMe: widget.likedMe,
                      // El aro de "tiene historia" sobre la foto de perfil
                      // pertenecía al mundo anterior (tira de stories + feed de
                      // perfiles). Aquí ya no puede darse: si hay historias, la
                      // tarjeta es la pila, no este perfil.
                      hasStory: false,
                      storySeen: widget.storySeen,
                      onOpenStory: widget.onOpenStory,
                      onRespondToPhoto: widget.onRespondToPhoto,
                      onRespondToPrompt: widget.onRespondToPrompt,
                    ),
                  ),
                ),
              );

        // Drag SOLO horizontal -> el scroll vertical interno sigue funcionando.
        return GestureDetector(
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(
              angle: angle,
              child: Stack(
                children: <Widget>[
                  body,
                  // Guideline 1.2: acceso permanente a Reportar / Bloquear
                  // sobre la propia tarjeta del feed. La marcha atrás va a su
                  // lado y NO abajo a la izquierda: ahí la tarjeta ya tiene el
                  // botón de Attra a la foto y el badge de "te dio like" ocupa
                  // la esquina de arriba.
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _RewindCardButton(
                          state: widget.rewind,
                          busy: widget.rewinding,
                          waiting: widget.pendingSend,
                          onPressed: widget.onRewind,
                        ),
                        const SizedBox(width: 8),
                        _SafetyCardButton(onPressed: widget.onSafetyMenu),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 24,
                    left: 20,
                    child: _SwipeStamp(
                      progress: likeOpacity,
                      icon: Icons.check_rounded,
                      color: context.colors.accent,
                      semanticLabel: 'Me interesa',
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: 20,
                    child: _SwipeStamp(
                      progress: nopeOpacity,
                      icon: Icons.close_rounded,
                      color: context.colors.textSecondary,
                      semanticLabel: 'Paso',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Marcha atrás en la tarjeta del feed.
///
/// SIEMPRE visible, en los tres tramos:
/// - Free: dorado (como el Attra), porque es el gancho. Al pulsarlo cuenta qué
///   da cada plan y abre el paywall; no se pinta apagado porque un botón gris
///   que no responde parece un fallo, no una función de pago.
/// - Plus/Pro con algo guardado: blanco y con contador cuando hay más de uno.
/// - Plus/Pro sin nada: atenuado, pero SIGUE respondiendo para poder decir que
///   no queda nada que deshacer.
class _RewindCardButton extends StatelessWidget {
  const _RewindCardButton({
    required this.state,
    required this.onPressed,
    this.busy = false,
    this.waiting = false,
  });

  final RewindState state;
  final VoidCallback onPressed;

  /// Deshaciendo ahora mismo: gira.
  final bool busy;

  /// Esperando a que el gesto anterior llegue al servidor: no responde, pero
  /// tampoco gira (no hay nada que el usuario haya pedido todavía).
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final bool locked = state.status == RewindStatus.locked;
    final bool empty = state.status == RewindStatus.empty;
    final Color color = locked
        ? AppColors.gold
        : empty
            ? Colors.white38
            : Colors.white;
    final String? counter = state.counterLabel;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          IconButton(
            key: const ValueKey<String>('feed-rewind-button'),
            tooltip: state.hint,
            onPressed: (busy || waiting) ? null : onPressed,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(Icons.replay_rounded, color: color, size: 22),
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
          ),
          if (counter != null)
            Positioned(
              right: 2,
              top: 2,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    counter,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón de seguridad de la tarjeta del feed: da acceso a Reportar y Bloquear
/// sin necesidad de match previo (App Store Guideline 1.2).
class _SafetyCardButton extends StatelessWidget {
  const _SafetyCardButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        key: const ValueKey<String>('feed-safety-button'),
        tooltip: 'Reportar o bloquear',
        onPressed: onPressed,
        icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Contenido del perfil con scroll vertical: foto principal con nombre,
/// panel de datos, bio, intereses y el resto de fotos debajo.
class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.profile,
    required this.onRespondToPhoto,
    required this.onRespondToPrompt,
    this.likedMe = false,
    this.hasStory = false,
    this.storySeen = false,
    this.onOpenStory,
  });

  final SeedProfile profile;
  final bool likedMe;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback? onOpenStory;
  final void Function(AdditionalPhoto photo, PhotoResponseKind kind)
      onRespondToPhoto;
  final void Function(PublicPrompt prompt) onRespondToPrompt;

  /// Fotos del perfil: la PRINCIPAL (photoUrl) primero y luego las adicionales
  /// (sin duplicar). Así la foto principal siempre se ve.
  List<AdditionalPhoto> get _photos {
    final List<AdditionalPhoto> out = <AdditionalPhoto>[];
    if (profile.photoUrl.isNotEmpty) {
      out.add(AdditionalPhoto(
          url: profile.photoUrl, storagePath: '', source: 'primary', order: 0));
    }
    for (final AdditionalPhoto p in profile.photos) {
      if (p.url.isNotEmpty && p.url != profile.photoUrl) out.add(p);
    }
    return out;
  }

  List<Widget> _interleavedMediaItems(
    List<AdditionalPhoto> photos,
    List<PublicPrompt> prompts,
  ) {
    final List<Widget> items = <Widget>[];
    int promptIndex = 0;

    for (final AdditionalPhoto photo in photos) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _PhotoWithAction(
            photo: photo,
            name: profile.displayName,
            onRespond: onRespondToPhoto,
          ),
        ),
      ));

      if (promptIndex < prompts.length) {
        final PublicPrompt prompt = prompts[promptIndex];
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _PromptCard(
            prompt: prompt,
            onRespond: () => onRespondToPrompt(prompt),
          ),
        ));
        promptIndex++;
      }
    }

    while (promptIndex < prompts.length) {
      final PublicPrompt prompt = prompts[promptIndex];
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _PromptCard(
          prompt: prompt,
          onRespond: () => onRespondToPrompt(prompt),
        ),
      ));
      promptIndex++;
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AdditionalPhoto> photos = _photos;
    final AdditionalPhoto? primary = photos.isNotEmpty ? photos.first : null;
    final List<AdditionalPhoto> restPhotos = photos.skip(1).toList();
    final String ageText = profile.age != null ? ', ${profile.age}' : '';
    final String place = <String>[profile.city, profile.country]
        .where((String s) => s.isNotEmpty)
        .join(', ');
    final String work = <String>[profile.jobTitle, profile.company]
        .where((String s) => s.isNotEmpty)
        .join(' · ');

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        // Foto principal con nombre/edad superpuestos y boton de respuesta.
        _PhotoWithAction(
          photo: primary,
          name: profile.displayName,
          onRespond: onRespondToPhoto,
          hasStory: hasStory,
          storySeen: storySeen,
          onOpenStory: onOpenStory,
          topBadge: likedMe ? const _LikedYouBadge() : null,
          overlay: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (profile.traveling) ...<Widget>[
                const _TravelingChip(),
                const SizedBox(height: 8),
              ],
              Text(
                '${profile.displayName}$ageText',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (place.isNotEmpty)
                _IconLine(icon: Icons.place_outlined, text: place),
            ],
          ),
        ),
        // Panel de datos.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (work.isNotEmpty)
                _DetailRow(icon: Icons.work_outline, text: work),
              if (profile.orientation.isNotEmpty)
                _DetailRow(
                  icon: Icons.favorite_border,
                  text: profile.orientation.map(_orientationLabel).join(', '),
                ),
              if (profile.bio.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(profile.bio, style: theme.textTheme.bodyLarge),
              ],
              if (profile.interests.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('Intereses', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.interests
                      .map((String i) => Chip(
                            label: Text(i),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
        // Resto de fotos con prompts intercalados, cada pieza respondible.
        ..._interleavedMediaItems(restPhotos, profile.profilePrompts),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Card de prompt en el perfil: pregunta pequeña, respuesta protagonista y
/// botón para responder (like/Attra con comentario).
class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onRespond});

  final PublicPrompt prompt;
  final VoidCallback onRespond;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(prompt.question,
              style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 0.3)),
          const SizedBox(height: 8),
          Text(prompt.answer,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRespond,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.favorite_border,
                      color: context.colors.accent, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto + boton flotante "Responder" (abre el sheet de like/Attra a esa foto).
class _PhotoWithAction extends StatelessWidget {
  const _PhotoWithAction({
    required this.photo,
    required this.name,
    required this.onRespond,
    this.overlay,
    this.topBadge,
    this.hasStory = false,
    this.storySeen = false,
    this.onOpenStory,
  });

  final AdditionalPhoto? photo;
  final String name;
  final void Function(AdditionalPhoto photo, PhotoResponseKind kind) onRespond;
  final Widget? overlay;
  final Widget? topBadge;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback? onOpenStory;

  @override
  Widget build(BuildContext context) {
    final AdditionalPhoto? p = photo;
    final String photoId = p == null
        ? ''
        : p.storagePath.isNotEmpty
            ? p.storagePath
            : p.url;
    return Stack(
      children: <Widget>[
        _PhotoBox(
          url: p?.url ?? '',
          name: name,
          overlay: overlay,
          hasStory: hasStory,
          storySeen: storySeen,
          onOpenStory: onOpenStory,
          overlayBottom: overlay != null && p != null ? 76 : 16,
        ),
        if (topBadge != null) Positioned(top: 14, left: 14, child: topBadge!),
        if (p != null) ...<Widget>[
          Positioned(
            left: 12,
            bottom: 12,
            child: _PhotoActionButton(
              key: ValueKey<String>('feed-photo-attra-action-$photoId'),
              label: 'Enviar un Attra a esta foto',
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.black,
              onTap: () => onRespond(p, PhotoResponseKind.attra),
              child: const Text(
                'A',
                style: TextStyle(
                  fontSize: 21,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _PhotoActionButton(
              key: ValueKey<String>('feed-photo-like-action-$photoId'),
              label: 'Enviar un Like o comentario a esta foto',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.black,
              onTap: () => onRespond(p, PhotoResponseKind.like),
              child: const Icon(Icons.add_comment_outlined, size: 22),
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoActionButton extends StatelessWidget {
  const _PhotoActionButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 46,
              child: IconTheme(
                data: IconThemeData(color: foregroundColor),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foregroundColor),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caja de foto con relación 3:4 y degradado opcional para el texto. Si el
/// perfil tiene story viva ([hasStory]) muestra un aro editorial y abre el
/// visor al pulsar.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({
    required this.url,
    required this.name,
    this.overlay,
    this.hasStory = false,
    this.storySeen = false,
    this.onOpenStory,
    this.overlayBottom = 16,
  });

  final String url;
  final String name;
  final Widget? overlay;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback? onOpenStory;
  final double overlayBottom;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (url.isNotEmpty)
            Positioned.fill(
              child: AttraImage(url: url, fallbackInitial: name),
            )
          else
            _PhotoFallback(name: name),
          if (overlay != null) ...<Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87
                  ],
                  stops: <double>[0.0, 0.55, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: overlayBottom,
              child: overlay!,
            ),
          ],
          // Aro de tinta (sin ver) o gris (ya visto) + badge "Historia" + tap.
          if (hasStory) ...<Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: storySeen
                            ? context.colors.textMuted
                            : context.colors.accent,
                        width: 3),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _StoryPill(seen: storySeen),
            ),
            // Capa de toque: abre el visor sin bloquear el swipe horizontal.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onOpenStory,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastilla "Historia" sobre la foto de quien tiene story viva. En gris si ya
/// se ha visto (se puede reabrir igualmente).
class _StoryPill extends StatelessWidget {
  const _StoryPill({this.seen = false});

  final bool seen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: seen ? Colors.black.withValues(alpha: 0.5) : null,
        gradient: seen ? null : const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.play_circle_fill_rounded,
              color: seen ? context.colors.textMuted : Colors.white, size: 15),
          const SizedBox(width: 5),
          Text('Historia',
              style: TextStyle(
                  color: seen ? context.colors.textSecondary : Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Distintivo "Te ha dado like" sobre la foto principal (Plus/Pro). Pill con
/// degradado de marca, glow y corazón.
/// Distintivo "De viaje" sobre la foto de quien está en modo viajes.
class _TravelingChip extends StatelessWidget {
  const _TravelingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.6)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.flight_takeoff_rounded,
              size: 13, color: AppColors.attraRed),
          SizedBox(width: 5),
          Text('De viaje',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LikedYouBadge extends StatelessWidget {
  const _LikedYouBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.favorite_rounded, size: 15, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'Te ha dado like',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

String _orientationLabel(String code) {
  const Map<String, String> labels = <String, String>{
    'straight': 'Hetero',
    'gay': 'Gay',
    'lesbian': 'Lesbiana',
    'bisexual': 'Bisexual',
    'pansexual': 'Pansexual',
    'asexual': 'Asexual',
    'demisexual': 'Demisexual',
    'queer': 'Queer',
    'questioning': 'Cuestionándose',
    'other': 'Otra',
  };
  return labels[code] ?? code;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}

/// Señal de swipe: un check o una X en un disco de vidrio.
///
/// Antes eran dos cajas con las palabras "LIKE" y "NOPE": lenguaje de otra app,
/// en inglés dentro de una app en español, y con el peso visual de un sello
/// gigante. Un icono se lee al instante, no necesita traducción y deja
/// respirar la foto, que es lo que el usuario está mirando.
///
/// La señal CRECE y se opaca con el arrastre ([progress] 0..1) en vez de solo
/// aparecer: así el gesto tiene respuesta continua y se nota cuánto falta para
/// que cuente.
class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({
    required this.progress,
    required this.icon,
    required this.color,
    required this.semanticLabel,
  });

  final double progress;
  final IconData icon;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final double t = progress.clamp(0.0, 1.0);
    if (t <= 0.01) return const SizedBox.shrink();
    // De 0.82 a 1.0: el disco "entra" con el gesto sin dar un salto brusco.
    final double scale = 0.82 + (0.18 * t);

    return Opacity(
      opacity: t,
      child: Transform.scale(
        scale: scale,
        child: Semantics(
          label: semanticLabel,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.bg.withValues(alpha: 0.42),
              border: Border.all(color: color, width: 2.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.45 * t),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 40),
          ),
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1D6A96), Color(0xFF14324A)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 96,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de fin de feed con acción principal (p. ej. "Segunda vuelta") y una
/// secundaria (p. ej. "Recargar"). Similar a AttraEmptyState pero con 2 botones.
class _FeedEndState extends StatelessWidget {
  const _FeedEndState({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  AppColors.attraRed.withValues(alpha: 0.22),
                  Colors.transparent,
                ]),
              ),
              // El icono del círculo estaba fijo a "replay" e ignoraba `icon`:
              // en estados que no son la segunda vuelta contaba otra historia.
              child: Icon(icon, size: 44, color: AppColors.attraRed),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(icon, size: 20),
              label: Text(primaryLabel),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
          ],
        ),
      ),
    );
  }
}
