import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_badges.dart';
import '../../../widgets/attra_image.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/presentation/chat_detail_screen.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_summary.dart';
import '../../profile/presentation/profile_view_screen.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../data/match_service.dart';
import '../domain/like.dart';
import '../domain/match_flow_result.dart';
import '../domain/user_match.dart';
import 'match_created_dialog.dart';

/// Centro de conexiones con tres bandejas inequívocas:
///  - Recibidos: personas que han dado like al usuario.
///  - Enviados: likes del usuario que siguen pendientes de respuesta.
///  - Matches: conexiones mutuas con acceso al chat y Attra Spark.
///
/// Ver quién ha dado like es funcionalidad base. El porcentaje de
/// compatibilidad sigue siendo una mejora Pro ([showCompatibility]).
class LikesReceivedScreen extends StatefulWidget {
  const LikesReceivedScreen({
    super.key,
    required this.currentUid,
    required this.matchService,
    required this.chatService,
    required this.summaries,
    this.showCompatibility = false,
    this.currentUserInterests = const <String>[],
    this.onImproveProfile,
    this.loadProfile,
    this.sparkService,
    this.sparkEnabled = false,
    this.currentUserPhotoUrl,
  });

  final String currentUid;
  final MatchService matchService;
  final ChatService chatService;
  final ProfileSummaryRepository summaries;

  /// Solo la IA Pro muestra el % de compatibilidad en las tarjetas.
  final bool showCompatibility;

  /// Intereses del usuario actual (para estimar afinidad real).
  final List<String> currentUserInterests;

  final VoidCallback? onImproveProfile;

  /// Carga el perfil completo por uid para abrir el visor de solo lectura.
  final Future<SeedProfile?> Function(String uid)? loadProfile;

  /// Attra Spark (opcional). Si está habilitado, el diálogo de match ofrece
  /// "Jugar 5 minutos". Si no, se comporta igual que siempre.
  final SparkService? sparkService;
  final bool sparkEnabled;
  final String? currentUserPhotoUrl;

  @override
  State<LikesReceivedScreen> createState() => _LikesReceivedScreenState();
}

class _LikesReceivedScreenState extends State<LikesReceivedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  StreamSubscription<List<Like>>? _receivedLikesSub;
  StreamSubscription<List<Like>>? _sentLikesSub;
  StreamSubscription<List<UserMatch>>? _matchesSub;
  List<Like>? _receivedLikes;
  List<Like>? _sentLikes;
  List<UserMatch>? _matches;
  Object? _receivedLikesError;
  Object? _sentLikesError;
  Object? _matchesError;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(covariant LikesReceivedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUid != widget.currentUid ||
        oldWidget.matchService != widget.matchService) {
      _bindStreams(reset: true);
    }
  }

  void _bindStreams({bool reset = false}) {
    unawaited(_receivedLikesSub?.cancel() ?? Future<void>.value());
    unawaited(_sentLikesSub?.cancel() ?? Future<void>.value());
    unawaited(_matchesSub?.cancel() ?? Future<void>.value());
    if (reset && mounted) {
      setState(() {
        _receivedLikes = null;
        _sentLikes = null;
        _matches = null;
        _receivedLikesError = null;
        _sentLikesError = null;
        _matchesError = null;
      });
    } else {
      _receivedLikes = null;
      _sentLikes = null;
      _matches = null;
      _receivedLikesError = null;
      _sentLikesError = null;
      _matchesError = null;
    }
    _receivedLikesSub =
        widget.matchService.observeReceivedLikes(widget.currentUid).listen(
      (List<Like> likes) {
        if (!mounted) return;
        setState(() {
          _receivedLikes = likes;
          _receivedLikesError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _receivedLikesError = error);
      },
    );
    _sentLikesSub =
        widget.matchService.observeSentLikes(widget.currentUid).listen(
      (List<Like> likes) {
        if (!mounted) return;
        setState(() {
          _sentLikes = likes;
          _sentLikesError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _sentLikesError = error);
      },
    );
    _matchesSub = widget.matchService.observeMatches(widget.currentUid).listen(
      (List<UserMatch> matches) {
        if (!mounted) return;
        setState(() {
          _matches = matches;
          _matchesError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _matchesError = error);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_receivedLikesSub?.cancel() ?? Future<void>.value());
    unawaited(_sentLikesSub?.cancel() ?? Future<void>.value());
    unawaited(_matchesSub?.cancel() ?? Future<void>.value());
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _respond(BuildContext context, Like like) async {
    try {
      final MatchFlowResult result =
          await widget.matchService.sendLike(like.fromUid);
      if (!context.mounted) return;
      switch (result.outcome) {
        case MatchOutcome.matched:
          final ProfileSummary other =
              await widget.summaries.fetch(like.fromUid);
          if (!context.mounted) return;
          final String chatId = result.chatId ?? '';
          // Si respondió con un comentario, abrimos directamente la
          // conversación: allí ya aparece su contexto original.
          if (like.hasComment && chatId.isNotEmpty) {
            _openChat(context, chatId, other);
            return;
          }
          await showMatchCreatedDialog(
            context,
            name: other.displayName,
            photoUrl: other.photoUrl,
            hasAttra: like.type.isAttra,
            currentUserPhotoUrl: widget.currentUserPhotoUrl,
            sharedInterests: _sharedInterests(other.interests),
            originComment: like.commentText,
            originPhotoUrl: like.targetPhotoUrlSnapshot,
            originType: like.targetType,
            onOpenChat: () => _openChat(context, chatId, other),
            onSendFirstMessage: chatId.isEmpty
                ? null
                : (String text) =>
                    widget.chatService.sendMessage(chatId: chatId, text: text),
            onPlaySpark: (widget.sparkEnabled &&
                    widget.sparkService != null &&
                    chatId.isNotEmpty)
                ? () => _playSpark(context, chatId, like.fromUid, other)
                : null,
          );
          return;
        case MatchOutcome.liked:
          _showFeedback(context, 'Like enviado.');
          return;
        case MatchOutcome.alreadyLiked:
          _showFeedback(context, 'Ya habías enviado un like a esta persona.');
          return;
        case MatchOutcome.limitReached:
          _showFeedback(context, 'Has alcanzado tu límite de likes de hoy.');
          return;
        case MatchOutcome.blocked:
          _showFeedback(context, 'No puedes interactuar con este perfil.');
          return;
        case MatchOutcome.insufficientAttras:
          _showFeedback(context, 'No tienes Attras suficientes.');
          return;
        case MatchOutcome.error:
          _showFeedback(context, 'No se pudo enviar el like.');
          return;
      }
    } on MatchServiceException catch (e) {
      if (!context.mounted) return;
      _showFeedback(context, e.message);
    } on Exception {
      if (!context.mounted) return;
      _showFeedback(context, 'No se pudo enviar el like.');
    }
  }

  void _showFeedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Invita a Attra Spark y abre la sala. Al terminar/salir, ofrece el chat.
  Future<void> _playSpark(BuildContext context, String matchId, String otherUid,
      ProfileSummary other) async {
    final SparkService? spark = widget.sparkService;
    if (spark == null) return;
    try {
      final String sessionId = await spark.invite(
        matchId: matchId,
        hostUid: widget.currentUid,
        guestUid: otherUid,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SparkGameScreen(
          service: spark,
          matchId: matchId,
          sessionId: sessionId,
          currentUid: widget.currentUid,
          otherName: other.displayName,
          onOpenChat: () => _openChat(context, matchId, other),
        ),
      ));
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar Attra Spark.')),
        );
      }
    }
  }

  void _openChat(BuildContext context, String chatId, ProfileSummary other) {
    if (chatId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatDetailScreen(
        chatId: chatId,
        currentUid: widget.currentUid,
        other: other,
        chatService: widget.chatService,
        matchService: widget.matchService,
      ),
    ));
  }

  /// Abre en solo lectura el perfil asociado a una conexión.
  Future<void> _openProfile(String uid) async {
    final Future<SeedProfile?> Function(String uid)? loader =
        widget.loadProfile;
    if (loader == null) return;
    final NavigatorState nav = Navigator.of(context);
    SeedProfile? profile;
    try {
      profile = await loader(uid);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el perfil.')),
      );
      return;
    }
    nav.push(MaterialPageRoute<void>(
      builder: (_) => ProfileViewScreen(
        profile: profile!,
        matchService: widget.matchService,
      ),
    ));
  }

  Future<void> _discard(BuildContext context, Like like) async {
    try {
      await widget.matchService.passProfile(like.fromUid);
      if (!context.mounted) return;
      _showFeedback(context, 'Like descartado.');
    } on MatchServiceException catch (error) {
      if (!context.mounted) return;
      _showFeedback(context, error.message);
    } on Exception {
      if (!context.mounted) return;
      _showFeedback(context, 'No se pudo descartar este like.');
    }
  }

  /// Intereses en común con el usuario actual (case-insensitive, máx. 6).
  List<String> _sharedInterests(List<String> other) {
    if (other.isEmpty || widget.currentUserInterests.isEmpty) {
      return const <String>[];
    }
    final Set<String> mine =
        widget.currentUserInterests.map((String s) => s.toLowerCase()).toSet();
    return other
        .where((String s) => mine.contains(s.toLowerCase()))
        .take(6)
        .toList(growable: false);
  }

  /// % de compatibilidad HONESTO: usa la señal del backend si existe; si no,
  /// estima afinidad por intereses compartidos (datos reales, no biométricos).
  /// Devuelve null si no hay base para mostrarlo (no se inventa un número).
  int? _compatibilityPct(ProfileSummary other, {double? score}) {
    if (score != null) {
      return (score.clamp(0, 1) * 100).round();
    }
    final List<String> shared = _sharedInterests(other.interests);
    if (shared.isEmpty) return null;
    return (70 + shared.length * 7).clamp(70, 98);
  }

  SliverGridDelegateWithFixedCrossAxisCount _gridDelegateFor(double width) {
    final int columns = width >= 620
        ? 3
        : width < 330
            ? 1
            : 2;
    final double gap = width < 380 ? AppSpacing.sm : AppSpacing.md;
    final double ratio = columns == 1
        ? 0.86
        : width < 380
            ? 0.56
            : 0.62;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: gap,
      mainAxisSpacing: gap,
      childAspectRatio: ratio,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _LikesTabBar(
          controller: _tabs,
          receivedCount: _receivedLikes?.length ?? 0,
          sentCount: _sentLikes?.length ?? 0,
          mutualCount: _matches?.length ?? 0,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _receivedTab(),
              _sentTab(),
              _mutualTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Pestaña 1: likes recibidos ───────────────────────────────────────────
  Widget _receivedTab() {
    final Object? error = _receivedLikesError;
    if (error != null) {
      return _LikesLoadError(onRetry: () => _bindStreams(reset: true));
    }
    final List<Like>? currentLikes = _receivedLikes;
    if (currentLikes == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.attraRed));
    }
    final List<Like> likes = currentLikes;
    if (likes.isEmpty) {
      return const _LikesEmpty(
        icon: Icons.favorite_border,
        title: 'Sin likes todavía',
        subtitle: 'Cuando alguien te dé like, aparecerá aquí en grande.',
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${likes.length} ${likes.length == 1 ? "persona quiere" : "personas quieren"} conocerte',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          sliver: SliverLayoutBuilder(
            builder: (BuildContext context, SliverConstraints constraints) {
              return SliverGrid(
                gridDelegate: _gridDelegateFor(constraints.crossAxisExtent),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    final Like like = likes[i];
                    return _LikeGridCard(
                      like: like,
                      summaries: widget.summaries,
                      showCompatibility: widget.showCompatibility,
                      compatibilityOf: (ProfileSummary s) =>
                          _compatibilityPct(s, score: like.compatibilityScore),
                      onRespond: () => _respond(context, like),
                      onDiscard: () => _discard(context, like),
                      onTap: widget.loadProfile == null
                          ? null
                          : () => _openProfile(like.fromUid),
                    );
                  },
                  childCount: likes.length,
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: _ImproveProfileBanner(onImprove: widget.onImproveProfile),
          ),
        ),
      ],
    );
  }

  // ── Pestaña 2: likes enviados pendientes ─────────────────────────────────
  Widget _sentTab() {
    final Object? error = _sentLikesError;
    if (error != null) {
      return _LikesLoadError(onRetry: () => _bindStreams(reset: true));
    }
    final List<Like>? currentLikes = _sentLikes;
    if (currentLikes == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.attraRed));
    }
    final List<Like> likes = currentLikes;
    if (likes.isEmpty) {
      return const _LikesEmpty(
        icon: Icons.favorite_border_rounded,
        title: 'No tienes likes pendientes',
        subtitle:
            'Los perfiles a los que des like aparecerán aquí hasta que haya match.',
      );
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${likes.length} ${likes.length == 1 ? "like enviado" : "likes enviados"} esperando respuesta',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          sliver: SliverLayoutBuilder(
            builder: (BuildContext context, SliverConstraints constraints) {
              return SliverGrid(
                gridDelegate: _gridDelegateFor(constraints.crossAxisExtent),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    final Like like = likes[i];
                    return _SentLikeGridCard(
                      like: like,
                      summaries: widget.summaries,
                      onTap: widget.loadProfile == null
                          ? null
                          : () => _openProfile(like.toUid),
                    );
                  },
                  childCount: likes.length,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Pestaña 3: matches ────────────────────────────────────────────────────
  Widget _mutualTab() {
    final Object? error = _matchesError;
    if (error != null) {
      return _LikesLoadError(onRetry: () => _bindStreams(reset: true));
    }
    final List<UserMatch>? currentMatches = _matches;
    if (currentMatches == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.attraRed));
    }
    final List<UserMatch> matches = currentMatches;
    if (matches.isEmpty) {
      return const _LikesEmpty(
        icon: Icons.favorite_rounded,
        title: 'Aún no hay match',
        subtitle:
            'Cuando os gustéis mutuamente, aparecerá aquí para empezar a chatear.',
      );
    }
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
          sliver: SliverLayoutBuilder(
            builder: (BuildContext context, SliverConstraints constraints) {
              return SliverGrid(
                gridDelegate: _gridDelegateFor(constraints.crossAxisExtent),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    final UserMatch m = matches[i];
                    final String otherUid = m.otherUid(widget.currentUid);
                    final String chatId = m.chatId ?? m.id;
                    return _MatchGridCard(
                      uid: otherUid,
                      summaries: widget.summaries,
                      hasAttra: m.hasAttra,
                      showCompatibility: widget.showCompatibility,
                      compatibilityOf: (ProfileSummary s) =>
                          _compatibilityPct(s),
                      onTap: () async {
                        final ProfileSummary other =
                            await widget.summaries.fetch(otherUid);
                        if (!context.mounted) return;
                        _openChat(context, chatId, other);
                      },
                    );
                  },
                  childCount: matches.length,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Navegación inequívoca del centro de conexiones.
class _LikesTabBar extends StatelessWidget {
  const _LikesTabBar({
    required this.controller,
    required this.receivedCount,
    required this.sentCount,
    required this.mutualCount,
  });

  final TabController controller;
  final int receivedCount;
  final int sentCount;
  final int mutualCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 430;
        return TabBar(
          controller: controller,
          isScrollable: false,
          labelPadding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
          indicatorColor: AppColors.attraRed,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.attraRed,
          unselectedLabelColor: context.colors.textSecondary,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 12 : 14,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: compact ? 12 : 14,
          ),
          dividerColor: context.colors.surfaceLine,
          tabs: <Widget>[
            Tab(
              child: _TabTitle(
                label: 'Recibidos',
                count: receivedCount,
              ),
            ),
            Tab(
              child: _TabTitle(
                label: 'Enviados',
                count: sentCount,
              ),
            ),
            Tab(
              child: _TabTitle(
                label: 'Matches',
                count: mutualCount,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TabTitle extends StatelessWidget {
  const _TabTitle({required this.label, this.count = 0});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count > 0) ...<Widget>[
          const SizedBox(width: 5),
          Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.attraRed,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tarjeta grande de like (foto a sangre, estilo Hinge/Bumble).
class _LikeGridCard extends StatelessWidget {
  const _LikeGridCard({
    required this.like,
    required this.summaries,
    required this.onRespond,
    required this.onDiscard,
    required this.compatibilityOf,
    this.showCompatibility = false,
    this.onTap,
  });

  final Like like;
  final ProfileSummaryRepository summaries;
  final VoidCallback onRespond;
  final VoidCallback onDiscard;
  final int? Function(ProfileSummary) compatibilityOf;
  final bool showCompatibility;
  final VoidCallback? onTap;

  /// Etiqueta de qué hizo esta persona.
  ({IconData icon, String text, Color color}) get _action {
    if (like.type.isAttra) {
      return (
        icon: Icons.star_rounded,
        text: 'Te envió un Attra',
        color: AppColors.gold
      );
    }
    if (like.isStoryTarget) {
      return (
        icon: Icons.auto_stories_rounded,
        text: 'Le gustó tu story',
        color: AppColors.coral
      );
    }
    if (like.isPromptTarget) {
      return (
        icon: Icons.chat_bubble_rounded,
        text: 'Respondió a tu pregunta',
        color: AppColors.coral
      );
    }
    if (like.isPhotoTarget) {
      return (
        icon: Icons.photo_rounded,
        text: 'Respondió a tu foto',
        color: AppColors.coral
      );
    }
    return (
      icon: Icons.favorite_rounded,
      text: 'Te dio like',
      color: AppColors.attraRed
    );
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String text, Color color}) action = _action;
    final AttraBadgeKind? premiumBadge = like.type.isAttra
        ? null
        : like.senderIsPro
            ? AttraBadgeKind.pro
            : like.senderIsPlus
                ? AttraBadgeKind.plus
                : null;
    final String? photoTargetUrl =
        like.isPhotoTarget ? like.targetPhotoUrlSnapshot : null;

    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(like.fromUid),
      initialData: summaries.peek(like.fromUid),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
        final int? pct = showCompatibility ? compatibilityOf(s) : null;
        return _ProfileCardShell(
          photoUrl: photoTargetUrl ?? s.photoUrl,
          name: s.displayName,
          verified: s.verified,
          age: s.age,
          headline: s.headline,
          location: s.location,
          compatibility: pct,
          comment: like.commentText,
          topBadge: (action.icon, action.text, action.color),
          premiumBadge: premiumBadge,
          onTap: onTap,
          footer: _RespondFooter(onRespond: onRespond, onDiscard: onDiscard),
        );
      },
    );
  }
}

/// Like enviado que aún espera respuesta.
class _SentLikeGridCard extends StatelessWidget {
  const _SentLikeGridCard({
    required this.like,
    required this.summaries,
    this.onTap,
  });

  final Like like;
  final ProfileSummaryRepository summaries;
  final VoidCallback? onTap;

  ({IconData icon, String text, Color color}) get _action {
    if (like.type.isAttra) {
      return (
        icon: Icons.star_rounded,
        text: 'Attra enviado',
        color: AppColors.gold,
      );
    }
    if (like.isStoryTarget) {
      return (
        icon: Icons.auto_stories_rounded,
        text: 'Like a su story',
        color: AppColors.coral,
      );
    }
    if (like.isPromptTarget) {
      return (
        icon: Icons.chat_bubble_rounded,
        text: 'Respuesta enviada',
        color: AppColors.coral,
      );
    }
    if (like.isPhotoTarget) {
      return (
        icon: Icons.photo_rounded,
        text: 'Like a su foto',
        color: AppColors.coral,
      );
    }
    return (
      icon: Icons.favorite_rounded,
      text: 'Like enviado',
      color: AppColors.attraRed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String text, Color color}) action = _action;
    final String? photoTargetUrl =
        like.isPhotoTarget ? like.targetPhotoUrlSnapshot : null;
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(like.toUid),
      initialData: summaries.peek(like.toUid),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary summary = snap.data ?? ProfileSummary.unknown;
        return _ProfileCardShell(
          photoUrl: photoTargetUrl ?? summary.photoUrl,
          name: summary.displayName,
          verified: summary.verified,
          age: summary.age,
          headline: summary.headline,
          location: summary.location,
          compatibility: null,
          comment: like.commentText,
          topBadge: (action.icon, action.text, action.color),
          premiumBadge: null,
          onTap: onTap,
          footer: const _PendingFooter(),
        );
      },
    );
  }
}

/// Tarjeta de match mutuo: foto clara, tap → chat.
class _MatchGridCard extends StatelessWidget {
  const _MatchGridCard({
    required this.uid,
    required this.summaries,
    required this.hasAttra,
    required this.compatibilityOf,
    required this.onTap,
    this.showCompatibility = false,
  });

  final String uid;
  final ProfileSummaryRepository summaries;
  final bool hasAttra;
  final int? Function(ProfileSummary) compatibilityOf;
  final VoidCallback onTap;
  final bool showCompatibility;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(uid),
      initialData: summaries.peek(uid),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
        final int? pct = showCompatibility ? compatibilityOf(s) : null;
        return _ProfileCardShell(
          photoUrl: s.photoUrl,
          name: s.displayName,
          verified: s.verified,
          age: s.age,
          headline: s.headline,
          location: s.location,
          compatibility: pct,
          topBadge: hasAttra
              ? (Icons.star_rounded, 'Match con Attra', AppColors.gold)
              : (Icons.favorite_rounded, 'Es match', AppColors.attraRed),
          premiumBadge: null,
          onTap: onTap,
          footer: const _ChatFooter(),
        );
      },
    );
  }
}

/// Carcasa visual compartida por las tarjetas de conexiones.
class _ProfileCardShell extends StatelessWidget {
  const _ProfileCardShell({
    required this.photoUrl,
    required this.name,
    required this.verified,
    required this.age,
    required this.headline,
    required this.location,
    required this.compatibility,
    required this.topBadge,
    required this.premiumBadge,
    required this.footer,
    required this.onTap,
    this.comment,
  });

  final String photoUrl;
  final String name;
  final bool verified;
  final int? age;
  final String headline;
  final String location;
  final int? compatibility;

  /// Comentario que dejó la persona junto al like (si lo hay).
  final String? comment;
  final (IconData, String, Color) topBadge;
  final AttraBadgeKind? premiumBadge;
  final Widget footer;
  final VoidCallback? onTap;

  bool get _hasComment => (comment ?? '').trim().isNotEmpty;

  String _compactBadgeText(String text) {
    final String raw = text.toLowerCase();
    if (raw.contains('pregunta')) return 'Pregunta';
    if (raw.contains('foto')) return 'Foto';
    if (raw.contains('story')) return 'Story';
    if (raw.contains('attra')) return 'Attra';
    if (raw.contains('match')) return 'Match';
    if (raw.contains('like')) return 'Like';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String nameLine = age != null ? '$name, $age' : name;
    final bool compactBadges = MediaQuery.sizeOf(context).width < 700;
    final String badgeText =
        compactBadges ? _compactBadgeText(topBadge.$2) : topBadge.$2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Material(
        color: context.colors.surface,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Foto (caché en disco + downscaling).
              Positioned.fill(
                child: AttraImage(url: photoUrl, fallbackInitial: name),
              ),

              // Velo inferior para legibilidad.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: <double>[0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // Badges superiores: en pantallas estrechas se compactan para no
              // pisarse entre si.
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compactBadges ? 7 : 8,
                              vertical: compactBadges ? 4 : 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusPill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(topBadge.$1,
                                    size: compactBadges ? 12 : 13,
                                    color: topBadge.$3),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    badgeText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compactBadges ? 10 : 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (premiumBadge != null) ...<Widget>[
                            const SizedBox(height: 6),
                            AttraPremiumBadge(premiumBadge!, compact: true),
                          ],
                        ],
                      ),
                    ),
                    if (compatibility != null) ...<Widget>[
                      SizedBox(width: compactBadges ? 5 : 8),
                      _CompatibilityChip(
                        pct: compatibility!,
                        compact: compactBadges,
                      ),
                    ],
                  ],
                ),
              ),

              // Bloque inferior: nombre + datos + footer.
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            nameLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              shadows: const <Shadow>[
                                Shadow(blurRadius: 6, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                        if (verified) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: AppColors.attraRed),
                        ],
                      ],
                    ),
                    if (headline.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85))),
                    ],
                    if (location.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.location_on_rounded,
                              size: 13, color: AppColors.attraRed),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85))),
                          ),
                        ],
                      ),
                    ],
                    if (_hasComment) ...<Widget>[
                      const SizedBox(height: 8),
                      _CommentBubble(text: comment!.trim()),
                    ],
                    const SizedBox(height: 10),
                    footer,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Burbuja con el comentario que dejó la persona junto a su like.
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.format_quote_rounded,
              size: 14, color: AppColors.attraRed),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.25,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip "92% compatibilidad" (solo IA Pro).
class _CompatibilityChip extends StatelessWidget {
  const _CompatibilityChip({required this.pct, this.compact = false});

  final int pct;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$pct%',
              style: TextStyle(
                  color: AppColors.attraRed,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w900,
                  height: 1.0)),
          Text(compact ? 'comp.' : 'compatibilidad',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: compact ? 7.5 : 8,
                  height: 1.1)),
        ],
      ),
    );
  }
}

/// Footer de un like recibido: responder o descartar.
class _RespondFooter extends StatelessWidget {
  const _RespondFooter({required this.onRespond, required this.onDiscard});

  final VoidCallback onRespond;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: InkWell(
              onTap: onRespond,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.action),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.favorite_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Responder',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.white.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onDiscard,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.close_rounded, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado no accionable de un like enviado.
class _PendingFooter extends StatelessWidget {
  const _PendingFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'Esperando respuesta',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer para matches: "Enviar mensaje".
class _ChatFooter extends StatelessWidget {
  const _ChatFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text('Enviar mensaje',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Banner inferior "Aumenta tus posibilidades".
class _ImproveProfileBanner extends StatelessWidget {
  const _ImproveProfileBanner({required this.onImprove});

  final VoidCallback? onImprove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.attraRed.withValues(alpha: 0.14),
            ),
            child: const Icon(Icons.photo_library_rounded,
                color: AppColors.attraRed, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Aumenta tus posibilidades',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  'Completa tu perfil y sube más fotos para recibir más likes cada día.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: context.colors.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onImprove,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.attraRed,
              side:
                  BorderSide(color: AppColors.attraRed.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
            ),
            child: const Text('Mejorar'),
          ),
        ],
      ),
    );
  }
}

class _LikesEmpty extends StatelessWidget {
  const _LikesEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: AppColors.attraRed),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: context.colors.textPrimary)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _LikesLoadError extends StatelessWidget {
  const _LikesLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.attraRed),
            const SizedBox(height: 12),
            Text(
              'No se pudieron cargar los likes',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: context.colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Reintenta en unos segundos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
