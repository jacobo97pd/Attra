import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
import '../../stories/presentation/stories_bar.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_states.dart';
import '../data/feed_metrics_service.dart';
import '../domain/boost_ranker.dart';
import '../domain/feed_filter.dart';
import '../domain/feed_filters.dart';
import '../domain/ranking.dart';
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
    this.aiVisualService,
    this.canUseVisualMatch = false,
    this.canSeeLikedMe = false,
    this.metrics,
    this.boostService,
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

  @override
  State<FeedScreen> createState() => _FeedScreenState();
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
  FeedFilters _filters = const FeedFilters();

  @override
  void initState() {
    super.initState();
    _load();
    _loadStoriesFlag();
  }

  @override
  void dispose() {
    // Vuelca impresiones pendientes (no perder telemetría al cerrar).
    widget.metrics?.flush();
    super.dispose();
  }

  /// Umbral de parecido (similitud coseno) para el filtro de IA visual.
  /// Solo se muestran candidatos con score >= este valor. El embedding de Vertex
  /// es ESTÉTICO (no identidad), así que las similitudes suelen ser altas; este
  /// valor se ajusta viendo los scores reales (se imprimen en debug abajo).
  static const double _kVisualMatchThreshold = 0.62;

  /// FILTRA la lista dejando SOLO los que se parecen a la foto de referencia
  /// (IA visual de Pro), ordenados de más a menos parecido.
  ///
  /// Best-effort: si el motor no está disponible (ranking vacío), devuelve la
  /// lista original sin filtrar para no dejar el feed en blanco por un fallo.
  Future<List<SeedProfile>> _sortByVisualReference(
      List<SeedProfile> profiles) async {
    try {
      final List<VisualMatch> ranking = await widget.aiVisualService!
          .getVisualMatches(profiles.map((SeedProfile p) => p.id).toList());
      // Motor no disponible (Vertex deshabilitado / sin referencia): no filtra.
      if (ranking.isEmpty) return profiles;

      if (kDebugMode) {
        for (final VisualMatch m in ranking) {
          debugPrint('[IA visual] ${m.uid}: ${m.score.toStringAsFixed(3)}');
        }
      }

      final Map<String, SeedProfile> byId = <String, SeedProfile>{
        for (final SeedProfile p in profiles) p.id: p,
      };
      // Solo los que superan el umbral, en orden de parecido (ranking ya viene
      // ordenado de mayor a menor score desde el backend).
      final List<SeedProfile> matches = <SeedProfile>[];
      for (final VisualMatch m in ranking) {
        if (m.score < _kVisualMatchThreshold) continue;
        final SeedProfile? p = byId[m.uid];
        if (p != null) matches.add(p);
      }
      return matches;
    } catch (_) {
      return profiles;
    }
  }

  Future<void> _loadStoriesFlag() async {
    final bool enabled = await widget.storyService?.storiesEnabled() ?? false;
    if (mounted) setState(() => _storiesEnabled = enabled);
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
      List<SeedProfile> filtered = FeedFilter.apply(
        profiles: all,
        myUid: myUid,
        myGender: widget.user?.gender ?? '',
        myInterestedIn: widget.user?.interestedIn ?? const <String>[],
        excludedUids: excluded,
        filters: _filters,
        myLat: widget.user?.latitude,
        myLng: widget.user?.longitude,
      );
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
      // Orden BASE orgánico (compatibilidad real). No salta filtros: solo ordena
      // lo ya filtrado. Los modos opt-in de abajo lo re-curan si están activos.
      filtered = activeBoosts.isEmpty
          ? RankingScorer.rank(profiles: filtered, me: widget.user)
          : BoostAwareRanker.rank(
              profiles: filtered,
              me: widget.user,
              activeBoosts: activeBoosts,
            );
      // Slow Dating (opt-in): cura el feed (menos perfiles, más afines e
      // intencionales). Solo altera ranking/visibilidad si el modo está activo.
      if (widget.user?.slowDatingEnabled ?? false) {
        filtered = SlowDatingRanker.curate(
          profiles: filtered,
          me: widget.user,
        );
      }
      // IA visual (Pro): reordena por parecido a la foto de referencia.
      if (_filters.sortByVisualReference &&
          widget.canUseVisualMatch &&
          widget.aiVisualService != null) {
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

  void _advance() {
    setState(() => _index += 1);
    _precacheNext();
    _recordCurrentImpression();
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
      final int next = _index + 1;
      if (next < _profiles.length) {
        toWarm.add(_profiles[next].primaryPhotoUrl);
        // También la primera adicional del siguiente (segunda imagen de su galería).
        final List<String> g = _profiles[next].galleryUrls;
        if (g.length > 1) toWarm.add(g[1]);
      }
      for (final String url in toWarm) {
        if (url.isNotEmpty) {
          precacheImage(NetworkImage(url), context).catchError((_) {});
        }
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onLikeProfile(SeedProfile profile) async {
    widget.metrics?.log(FeedMetricsService.likeSent,
        uid: _uid, targetUid: profile.id);
    _advance();
    await _sendAndHandle(
        () => widget.matchService.sendLike(profile.id), profile);
  }

  Future<void> _onPass(SeedProfile profile) async {
    widget.metrics?.log(FeedMetricsService.nopeSent,
        uid: _uid, targetUid: profile.id);
    _advance();
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
    widget.metrics?.log(FeedMetricsService.attraSent,
        uid: _uid, targetUid: profile.id);
    _advance();
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

  Future<void> _sendAndHandle(
      Future<MatchFlowResult> Function() call, SeedProfile profile) async {
    try {
      final MatchFlowResult result = await call();
      if (!mounted) return;
      switch (result.outcome) {
        case MatchOutcome.matched:
          widget.metrics?.log(FeedMetricsService.matchCreated,
              uid: _uid, targetUid: profile.id);
          await showMatchCreatedDialog(
            context,
            name: profile.displayName,
            photoUrl: profile.primaryPhotoUrl,
            hasAttra: false,
            originComment: result.message,
            onOpenChat: () => _openChat(result.chatId ?? '', profile),
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
        case MatchOutcome.alreadyLiked:
        case MatchOutcome.error:
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
    return SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: _storiesStrip()),
          filterButton,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _feedHeader(),
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

    final SeedProfile profile = _profiles[_index];
    final bool likedMe = _likedMeUids.contains(profile.id);
    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
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
                onLike: () => _onLikeProfile(profile),
                onPass: () => _onPass(profile),
                onRespondToPhoto: (AdditionalPhoto photo) =>
                    _onRespondToPhoto(profile, photo),
                onRespondToPrompt: (PublicPrompt prompt) =>
                    _onRespondToPrompt(profile, prompt),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CircleAction(
                  icon: Icons.close_rounded,
                  size: 58,
                  iconColor: AppColors.textSecondary,
                  borderColor: AppColors.surfaceLine,
                  tooltip: 'Pasar',
                  onPressed: () => _cardKey.currentState?.triggerSwipe(false),
                ),
                const SizedBox(width: 24),
                _CircleAction(
                  icon: Icons.star_rounded,
                  size: 52,
                  gradient: const <Color>[AppColors.wine, AppColors.gold],
                  glow: AppColors.gold,
                  tooltip: 'Enviar Attra',
                  onPressed: () => _onAttraProfile(profile),
                ),
                const SizedBox(width: 24),
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
  });

  final SeedProfile profile;
  final bool likedMe;
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
                      child: const _Stamp(
                          label: 'NOPE', color: AppColors.textSecondary),
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
  });

  final SeedProfile profile;
  final bool likedMe;
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
          topBadge: likedMe ? const _LikedYouBadge() : null,
          overlay: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
  });

  final AdditionalPhoto? photo;
  final String name;
  final void Function(AdditionalPhoto photo) onRespond;
  final Widget? overlay;
  final Widget? topBadge;

  @override
  Widget build(BuildContext context) {
    final AdditionalPhoto? p = photo;
    return Stack(
      children: <Widget>[
        _PhotoBox(url: p?.url ?? '', name: name, overlay: overlay),
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

/// Caja de foto con relación 3:4 y degradado opcional para el texto.
class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.url, required this.name, this.overlay});

  final String url;
  final String name;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (url.isNotEmpty)
            Image.network(
              url,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              loadingBuilder: (BuildContext context, Widget child,
                  ImageChunkEvent? progress) {
                if (progress == null) {
                  return child;
                }
                return const ColoredBox(
                  color: Color(0xFFE0E0E0),
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, __, ___) => _PhotoFallback(name: name),
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
        ],
      ),
    );
  }
}

/// Distintivo "Te ha dado like" sobre la foto principal (Plus/Pro). Pill con
/// degradado de marca, glow y corazón.
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
        color: AppColors.black.withValues(alpha: 0.55),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final List<Color>? gradient;
  final Color? glow;
  final Color? iconColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gradient == null ? AppColors.surfaceHigh : null,
                gradient: gradient == null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient!),
                border: Border.all(
                    color: borderColor ?? Colors.white.withValues(alpha: 0.08)),
                boxShadow: glow == null
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
                  color: iconColor ?? AppColors.textPrimary, size: size * 0.46),
            ),
          ),
        ),
      ),
    );
  }
}
