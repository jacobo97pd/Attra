import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../ads/presentation/feed_native_ad_card.dart';
import '../../ai_visual/data/ai_visual_service.dart';
import '../../auth/domain/app_user.dart';
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
import '../../monetization/data/boost_service.dart';
import '../../monetization/domain/boost.dart';
import '../../stories/data/story_service.dart';
import '../../stories/domain/story.dart';
import '../../stories/presentation/stories_bar.dart';
import '../../stories/presentation/story_viewer_screen.dart';
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
import '../domain/ranking.dart';
import '../domain/ranking_config.dart';
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
    required this.chatService,
    this.attrasBalance = 0,
    this.canComment = false,
    this.reloadToken = 0,
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
  });

  final AppUser? user;
  final Future<List<SeedProfile>> Function() onLoadSeedProfiles;
  final MatchService matchService;
  final ChatService chatService;
  final StoryService? storyService;
  final int attrasBalance;

  /// Cambia (lo incrementa HomeShell al abrir la pestaña Feed) para forzar una
  /// recarga que re-aplica la exclusion (p.ej. tras un match desde Likes).
  final int reloadToken;

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

enum _FeedActionKind {
  like('like'),
  pass('pass');

  const _FeedActionKind(this.wireName);
  final String wireName;
}

class _FeedRewindAction {
  const _FeedRewindAction({
    required this.index,
    required this.targetUid,
    required this.kind,
  });

  final int index;
  final String targetUid;
  final _FeedActionKind kind;
}

class _FeedScreenState extends State<FeedScreen> {
  final GlobalKey<_SwipeCardState> _cardKey = GlobalKey<_SwipeCardState>();
  bool _loading = true;
  String? _error;
  List<SeedProfile> _profiles = const <SeedProfile>[];
  int _index = 0;
  Set<String> _excluded = const <String>{};
  Set<String> _likedMeUids = const <String>{};
  Map<String, ActiveBoost> _activeBoostsByUid = const <String, ActiveBoost>{};
  bool _storiesEnabled = false;
  // Stories vivas agrupadas por dueño: para pintar el aro rojizo en la foto
  // principal del feed y abrir el visor al pulsar.
  Map<String, List<Story>> _storiesByOwner = const <String, List<Story>>{};
  StreamSubscription<List<Story>>? _storiesSub;
  // Stories ya vistas (por id) en esta sesión: el aro pasa a gris pero se puede
  // reabrir cuantas veces se quiera.
  final Set<String> _seenStoryIds = <String>{};
  bool _rewinding = false;
  List<_FeedRewindAction> _rewindHistory = const <_FeedRewindAction>[];
  FeedFilters _filters = const FeedFilters();

  // Ubicación del dispositivo como RESPALDO cuando el perfil del usuario no tiene
  // coordenadas guardadas: así la distancia del feed siempre tiene un "yo".
  double? _deviceLat;
  double? _deviceLng;

  /// Lat efectiva del usuario: la guardada o, si falta, la del dispositivo.
  double? get _effectiveLat => widget.user?.latitude ?? _deviceLat;
  double? get _effectiveLng => widget.user?.longitude ?? _deviceLng;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStoriesFlag();
    _ensureDeviceLocation();
  }

  /// Asegura una ubicación para el usuario cuando su perfil no tiene coords:
  /// usa la última conocida y, si no hay, pide la actual (con permiso). Así la
  /// distancia del feed siempre funciona. Best-effort: nunca rompe.
  Future<void> _ensureDeviceLocation() async {
    if (widget.user?.latitude != null) return; // ya hay coords guardadas
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      // getLastKnownPosition no está soportado en web: ahí se pide la actual.
      Position? pos = kIsWeb ? null : await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 6),
          onTimeout: () => throw TimeoutException('geo'));
      if (!mounted) return;
      setState(() {
        _deviceLat = pos!.latitude;
        _deviceLng = pos.longitude;
      });
      _load();
    } catch (_) {/* sin ubicación: el feed cae al filtro por país */}
  }

  @override
  void dispose() {
    // Vuelca impresiones pendientes (no perder telemetría al cerrar).
    widget.metrics?.flush();
    _storiesSub?.cancel();
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
  /// filtro visual es peor mostrar el feed organico como falso positivo.
  Future<List<SeedProfile>> _sortByVisualReference(
      List<SeedProfile> profiles) async {
    try {
      final List<VisualMatch> ranking = await widget.aiVisualService!
          .getVisualMatches(profiles.map((SeedProfile p) => p.id).toList());
      // Motor no disponible (Vertex deshabilitado / sin referencia): sin falsos
      // positivos.
      if (ranking.isEmpty) return const <SeedProfile>[];

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
      return matches;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IA visual] error al ordenar: $e');
      }
      return const <SeedProfile>[];
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

  Future<void> _loadStoriesFlag() async {
    final bool enabled = await widget.storyService?.storiesEnabled() ?? false;
    if (mounted) setState(() => _storiesEnabled = enabled);
    if (enabled) _bindStories();
  }

  /// Escucha las stories vivas y las agrupa por dueño para resaltar la foto
  /// principal de quien tiene historia (aro rojizo + visor al pulsar).
  void _bindStories() {
    final StoryService? svc = widget.storyService;
    final String myUid = widget.user?.uid ?? '';
    if (svc == null) return;
    _storiesSub?.cancel();
    _storiesSub = svc.observeLiveStories(excludeUid: myUid).listen(
      (List<Story> stories) {
        if (!mounted) return;
        final Map<String, List<Story>> grouped = <String, List<Story>>{};
        for (final Story s in stories) {
          (grouped[s.ownerUid] ??= <Story>[]).add(s);
        }
        setState(() => _storiesByOwner = grouped);
      },
      onError: (Object _) {/* sin stories: el feed sigue igual */},
    );
  }

  /// True si TODAS las stories vivas de [ownerUid] ya se han visto (aro gris).
  bool _ownerStoriesSeen(String ownerUid) {
    final List<Story>? stories = _storiesByOwner[ownerUid];
    if (stories == null || stories.isEmpty) return false;
    return stories.every((Story s) => _seenStoryIds.contains(s.storyId));
  }

  void _openStoryFor(String ownerUid) {
    final StoryService? svc = widget.storyService;
    final List<Story>? stories = _storiesByOwner[ownerUid];
    if (svc == null || stories == null || stories.isEmpty) return;
    // Marca como vistas (el aro pasa a gris); se puede reabrir sin límite.
    setState(() {
      for (final Story s in stories) {
        _seenStoryIds.add(s.storyId);
      }
    });
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(
        stories: stories,
        initialIndex: 0,
        currentUid: widget.user?.uid ?? '',
        storyService: svc,
      ),
    ));
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al volver a la pestaña Feed, recarga y re-excluye (matched/liked/pasados).
    if (oldWidget.reloadToken != widget.reloadToken && !_loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _activeBoostsByUid = const <String, ActiveBoost>{};
    });
    try {
      final String myUid = widget.user?.uid ?? '';
      final List<SeedProfile> all = await widget.onLoadSeedProfiles();
      // Excluidos (likeados/pasados/matcheados/bloqueados). Best-effort: si la
      // lectura falla, no vaciamos el feed.
      Set<String> excluded = const <String>{};
      if (myUid.isNotEmpty) {
        try {
          excluded = await widget.matchService.fetchExcludedUids(myUid);
        } catch (_) {
          excluded = const <String>{};
        }
      }
      if (!mounted) {
        return;
      }
      // Búsqueda visual (Pro): buscar tu "tipo" es GLOBAL → no restringe por
      // ubicación ni curación de Slow Dating; la IA evalúa a todos los candidatos.
      final bool visualSearch = _filters.sortByVisualReference &&
          widget.canUseVisualMatch &&
          widget.aiVisualService != null;
      // Modo viajes: cuando viajas, el feed se CENTRA en el destino (se ignora
      // la distancia real y se usa el PAÍS de destino para la relevancia).
      final bool traveling =
          !visualSearch && (widget.user?.isTraveling ?? false);
      List<SeedProfile> filtered = FeedFilter.apply(
        profiles: all,
        myUid: myUid,
        myGender: widget.user?.gender ?? '',
        myInterestedIn: widget.user?.interestedIn ?? const <String>[],
        excludedUids: excluded,
        filters: _filters,
        // En viaje/búsqueda visual no hay "mi" lat/lng (no filtra por distancia).
        myLat: (traveling || visualSearch) ? null : _effectiveLat,
        myLng: (traveling || visualSearch) ? null : _effectiveLng,
        myCountry: visualSearch
            ? ''
            : (traveling
                ? (widget.user?.travelCountry ?? '')
                : (widget.user?.countryName ?? '')),
        defaultMaxKm: visualSearch ? null : widget.user?.maxDistanceKm,
      );
      if (traveling) {
        filtered = _applyTravel(filtered);
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
      if (!mounted) return;
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
        if (!mounted) return;
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
      if (!visualSearch && (widget.user?.slowDatingEnabled ?? false)) {
        filtered = SlowDatingRanker.curate(
          profiles: filtered,
          me: widget.user,
        );
      }
      // IA visual (Pro): ordena por parecido a la foto de referencia.
      if (visualSearch) {
        filtered = await _sortByVisualReference(filtered);
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
        if (likedMe.isNotEmpty) {
          // Partición estable: primero quienes te dieron like, resto después.
          final List<SeedProfile> liked = <SeedProfile>[];
          final List<SeedProfile> rest = <SeedProfile>[];
          for (final SeedProfile p in filtered) {
            (likedMe.contains(p.id) ? liked : rest).add(p);
          }
          filtered = <SeedProfile>[...liked, ...rest];
        }
      }
      if (!mounted) return;
      setState(() {
        _excluded = excluded;
        _likedMeUids = likedMe;
        _activeBoostsByUid = activeBoosts;
        _profiles = filtered;
        _index = 0;
        _pendingAd = false;
        _rewindHistory = const <_FeedRewindAction>[];
        _rewinding = false;
        _loading = false;
      });
      _precacheNext();
      _recordCurrentImpression();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'No se pudo cargar el feed. ($error)';
        _loading = false;
      });
    }
  }

  String get _uid => widget.user?.uid ?? '';

  /// Un anuncio cada N perfiles vistos (nunca al inicio).
  static const int _adFrequency = 7;
  int _swipesSinceAd = 0;
  bool _pendingAd = false;

  void _advance({
    _FeedActionKind? rewindAction,
    bool clearRewindHistory = false,
  }) {
    // Tras varios perfiles, inserta una ad card (si procede). No al arrancar.
    _swipesSinceAd++;
    final bool showAd = widget.adsEnabled && _swipesSinceAd >= _adFrequency;
    setState(() {
      if (clearRewindHistory) {
        _rewindHistory = const <_FeedRewindAction>[];
      } else if (rewindAction != null && _index < _profiles.length) {
        final _FeedRewindAction action = _FeedRewindAction(
          index: _index,
          targetUid: _profiles[_index].id,
          kind: rewindAction,
        );
        _rewindHistory = widget.rewindUnlimited
            ? <_FeedRewindAction>[..._rewindHistory, action]
            : <_FeedRewindAction>[action];
      }
      _index += 1;
      if (showAd) {
        _swipesSinceAd = 0;
        _pendingAd = true;
      }
    });
    _precacheNext();
    _recordCurrentImpression();
  }

  void _removeRewindActionFor(String targetUid) {
    if (_rewindHistory.isEmpty) return;
    final List<_FeedRewindAction> next = _rewindHistory
        .where((_FeedRewindAction action) => action.targetUid != targetUid)
        .toList(growable: false);
    if (next.length == _rewindHistory.length) return;
    setState(() => _rewindHistory = next);
  }

  /// Registra como "mostrado" el perfil actualmente visible (impresión).
  void _recordCurrentImpression() {
    if (_uid.isEmpty || _index >= _profiles.length) return;
    final SeedProfile profile = _profiles[_index];
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onRewind() async {
    if (!widget.canRewind) {
      _snack('Volver atras es para Plus y Pro.');
      widget.onOpenUpgrade?.call();
      return;
    }
    if (_rewinding) return;
    if (_rewindHistory.isEmpty) {
      _snack('No hay ningun perfil anterior para volver.');
      return;
    }

    final _FeedRewindAction action = _rewindHistory.last;
    setState(() => _rewinding = true);
    try {
      await widget.matchService.rewindFeedAction(
        targetUid: action.targetUid,
        action: action.kind.wireName,
      );
      if (!mounted) return;
      setState(() {
        _pendingAd = false;
        if (_profiles.isEmpty) {
          _index = 0;
        } else {
          final int maxIndex = _profiles.length - 1;
          _index = action.index < 0
              ? 0
              : action.index > maxIndex
                  ? maxIndex
                  : action.index;
        }
        _rewindHistory = _rewindHistory
            .sublist(0, _rewindHistory.length - 1)
            .toList(growable: false);
        _excluded = <String>{..._excluded}..remove(action.targetUid);
        _rewinding = false;
      });
      _precacheNext();
      _recordCurrentImpression();
    } on MatchServiceException catch (error) {
      _snack(error.message);
    } finally {
      if (mounted && _rewinding) {
        setState(() => _rewinding = false);
      }
    }
  }

  Future<void> _onLikeProfile(SeedProfile profile) async {
    widget.metrics
        ?.log(FeedMetricsService.likeSent, uid: _uid, targetUid: profile.id);
    _advance(rewindAction: _FeedActionKind.like);
    await _sendAndHandle(
        () => widget.matchService.sendLike(profile.id), profile);
  }

  Future<void> _onPass(SeedProfile profile) async {
    widget.metrics
        ?.log(FeedMetricsService.nopeSent, uid: _uid, targetUid: profile.id);
    _advance(rewindAction: _FeedActionKind.pass);
    try {
      await widget.matchService.passProfile(profile.id);
    } catch (_) {
      // Descartar es best-effort.
    }
  }

  Future<void> _onAttraProfile(SeedProfile profile) async {
    if (widget.attrasBalance <= 0) {
      _snack('No tienes Attras suficientes.');
      return;
    }
    widget.metrics
        ?.log(FeedMetricsService.attraSent, uid: _uid, targetUid: profile.id);
    _advance(clearRewindHistory: true);
    await _sendAndHandle(
        () => widget.matchService.sendAttra(profile.id), profile);
  }

  Future<void> _onRespondToPhoto(
      SeedProfile profile, AdditionalPhoto photo) async {
    final PhotoResponseResult? res = await PhotoResponseSheet.show(
      context,
      name: profile.displayName,
      photoUrl: photo.url,
      attraBalance: widget.attrasBalance,
      canComment: widget.canComment,
    );
    if (res == null || !mounted) return;
    final String? photoId =
        photo.storagePath.isNotEmpty ? photo.storagePath : null;
    if (res.kind == PhotoResponseKind.like) {
      await _sendAndHandle(
        () => widget.matchService
            .sendLike(profile.id, targetPhotoId: photoId, comment: res.comment),
        profile,
      );
    } else {
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

  Future<void> _sendAndHandle(
      Future<MatchFlowResult> Function() call, SeedProfile profile) async {
    try {
      final MatchFlowResult result = await call();
      if (!mounted) return;
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
          );
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

  void _openChat(String chatId, SeedProfile profile) {
    if (chatId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatDetailScreen(
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

  Widget _storiesStrip() {
    final StoryService? svc = widget.storyService;
    final String uid = widget.user?.uid ?? '';
    if (!_storiesEnabled || svc == null || uid.isEmpty) {
      return const SizedBox(height: 48);
    }
    return StoriesBar(
      currentUid: uid,
      currentName: widget.user?.displayName ?? 'Tú',
      currentPhotoUrl: widget.user?.photoUrl ?? '',
      storyService: svc,
      // Solo se ven historias de personas con las que hay match.
      matchService: widget.matchService,
      excludedOwners: _excluded,
    );
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
                child: Text('${_filters.activeCount}',
                    style: const TextStyle(fontSize: 10, color: Colors.white)),
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
    return SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: _storiesStrip()),
          travelButton,
          filterButton,
        ],
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _feedHeader(),
        if (widget.user?.isTraveling ?? false) _travelBanner(),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
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
      return AttraEmptyState(
        icon: Icons.search_off,
        title: 'No hay más personas por el momento',
        message:
            'Cuando entren nuevos perfiles compatibles aparecerán aquí. No volverás a ver a quien ya likeaste o pasaste.',
        actionLabel: 'Recargar',
        onAction: _load,
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
    final bool rewindEnabled =
        !widget.canRewind || (_rewindHistory.isNotEmpty && !_rewinding);
    final String rewindTooltip = widget.canRewind
        ? widget.rewindUnlimited
            ? 'Volver atras'
            : 'Volver atras (1 paso)'
        : 'Volver atras (Plus/Pro)';
    return SafeArea(
      child: Stack(
        children: <Widget>[
          // La tarjeta ocupa toda la altura disponible: la foto se ve más grande.
          Positioned.fill(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              // Quien te dio like se ve MÁS GRANDE: menos margen alrededor.
              padding: likedMe
                  ? const EdgeInsets.fromLTRB(4, 4, 4, 4)
                  : const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: _SwipeCard(
                key: _cardKey,
                profile: profile,
                likedMe: likedMe,
                hasStory: _storiesByOwner.containsKey(profile.id),
                storySeen: _ownerStoriesSeen(profile.id),
                onOpenStory: () => _openStoryFor(profile.id),
                onLike: () => _onLikeProfile(profile),
                onPass: () => _onPass(profile),
                onRespondToPhoto: (AdditionalPhoto photo) =>
                    _onRespondToPhoto(profile, photo),
                onRespondToPrompt: (PublicPrompt prompt) =>
                    _onRespondToPrompt(profile, prompt),
              ),
            ),
          ),
          // Degradado suave detrás de los botones para que se lean sobre fotos
          // claras. No captura toques (IgnorePointer) para no robar el scroll.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Botones de acción FLOTANDO sobre la imagen (abajo).
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CircleAction(
                  icon: widget.canRewind
                      ? Icons.undo_rounded
                      : Icons.lock_outline_rounded,
                  size: 48,
                  iconColor: widget.canRewind
                      ? AppColors.gold
                      : context.colors.textSecondary,
                  borderColor: widget.canRewind
                      ? AppColors.gold.withValues(alpha: 0.38)
                      : context.colors.surfaceLine,
                  tooltip: rewindTooltip,
                  enabled: rewindEnabled,
                  onPressed: _onRewind,
                ),
                const SizedBox(width: 12),
                _CircleAction(
                  icon: Icons.close_rounded,
                  size: 58,
                  iconColor: context.colors.textSecondary,
                  borderColor: context.colors.surfaceLine,
                  tooltip: 'Pasar',
                  onPressed: () => _cardKey.currentState?.triggerSwipe(false),
                ),
                const SizedBox(width: 16),
                _CircleAction(
                  icon: Icons.star_rounded,
                  size: 52,
                  gradient: const <Color>[AppColors.wine, AppColors.gold],
                  glow: AppColors.gold,
                  tooltip: 'Enviar Attra',
                  onPressed: () => _onAttraProfile(profile),
                ),
                const SizedBox(width: 16),
                _CircleAction(
                  icon: Icons.favorite_rounded,
                  size: 66,
                  gradient: AppColors.action,
                  glow: AppColors.attraRed,
                  tooltip: 'Me gusta',
                  onPressed: () => _cardKey.currentState?.triggerSwipe(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeCard extends StatefulWidget {
  const _SwipeCard({
    super.key,
    required this.profile,
    required this.onLike,
    required this.onPass,
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
  final VoidCallback onLike;
  final VoidCallback onPass;
  final void Function(AdditionalPhoto photo) onRespondToPhoto;
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

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dx.abs() > _threshold) {
      triggerSwipe(_dx > 0);
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
                  // Realce para quien te dio like: borde + glow rojo de marca.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: widget.likedMe
                          ? Border.all(color: AppColors.attraRed, width: 2)
                          : null,
                      boxShadow: widget.likedMe
                          ? <BoxShadow>[
                              BoxShadow(
                                color:
                                    AppColors.attraRed.withValues(alpha: 0.45),
                                blurRadius: 26,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: _ProfileDetail(
                          profile: widget.profile,
                          likedMe: widget.likedMe,
                          hasStory: widget.hasStory,
                          storySeen: widget.storySeen,
                          onOpenStory: widget.onOpenStory,
                          onRespondToPhoto: widget.onRespondToPhoto,
                          onRespondToPrompt: widget.onRespondToPrompt,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 24,
                    left: 20,
                    child: Opacity(
                      opacity: likeOpacity,
                      child: const _Stamp(
                          label: 'LIKE', color: AppColors.attraRed),
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: 20,
                    child: Opacity(
                      opacity: nopeOpacity,
                      child: _Stamp(
                          label: 'NOPE', color: context.colors.textSecondary),
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
  final void Function(AdditionalPhoto photo) onRespondToPhoto;
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
        // Hueco extra para que el último contenido no quede bajo los botones
        // flotantes (≈ alto del botón de like + margen).
        const SizedBox(height: 96),
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
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.favorite_border,
                      color: AppColors.attraRed, size: 22),
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
  final void Function(AdditionalPhoto photo) onRespond;
  final Widget? overlay;
  final Widget? topBadge;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback? onOpenStory;

  @override
  Widget build(BuildContext context) {
    final AdditionalPhoto? p = photo;
    return Stack(
      children: <Widget>[
        _PhotoBox(
          url: p?.url ?? '',
          name: name,
          overlay: overlay,
          hasStory: hasStory,
          storySeen: storySeen,
          onOpenStory: onOpenStory,
        ),
        if (topBadge != null) Positioned(top: 14, left: 14, child: topBadge!),
        if (p != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onRespond(p),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.add_comment_outlined,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Caja de foto con relación 3:4 y degradado opcional para el texto. Si el
/// perfil tiene story viva ([hasStory]) muestra un aro/borde rojizo con glow y
/// abre el visor al pulsar.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({
    required this.url,
    required this.name,
    this.overlay,
    this.hasStory = false,
    this.storySeen = false,
    this.onOpenStory,
  });

  final String url;
  final String name;
  final Widget? overlay;
  final bool hasStory;
  final bool storySeen;
  final VoidCallback? onOpenStory;

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
            Positioned(left: 18, right: 18, bottom: 16, child: overlay!),
          ],
          // Aro rojizo (sin ver) o gris (ya visto) + badge "Historia" + tap.
          if (hasStory) ...<Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: storySeen
                            ? context.colors.textMuted
                            : AppColors.attraRed,
                        width: 3),
                    boxShadow: storySeen
                        ? null
                        : <BoxShadow>[
                            BoxShadow(
                              color: AppColors.attraRed.withValues(alpha: 0.55),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ],
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
        boxShadow: seen
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: AppColors.attraRed.withValues(alpha: 0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
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
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.attraRed.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
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

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.bg.withValues(alpha: 0.55),
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
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

/// Botón circular de acción del feed. Relleno grafito por defecto, o degradado
/// + glow para las acciones destacadas (Attra, Like).
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 58,
    this.gradient,
    this.glow,
    this.iconColor,
    this.borderColor,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final List<Color>? gradient;
  final Color? glow;
  final Color? iconColor;
  final Color? borderColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : 0.42,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onPressed : null,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gradient == null ? context.colors.surfaceHigh : null,
                  gradient: gradient == null
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient!),
                  border: Border.all(
                      color:
                          borderColor ?? Colors.white.withValues(alpha: 0.08)),
                  boxShadow: glow == null || !enabled
                      ? null
                      : <BoxShadow>[
                          BoxShadow(
                            color: glow!.withValues(alpha: 0.45),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: Icon(icon,
                    color: iconColor ?? context.colors.textPrimary,
                    size: size * 0.46),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
