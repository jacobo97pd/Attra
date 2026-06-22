import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../theme/app_colors.dart';
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

/// Bandeja de likes en GRID de fotos grandes (estilo Hinge/Bumble) con dos
/// pestañas: "Quién te gusta" (likes recibidos) y "Me gustas mutuamente"
/// (matches). Reglas premium:
///  - Free (sin Plus/Pro) NO puede ver quién le dio like: las tarjetas salen
///    difuminadas con "Desliza para ver" y un muro de upgrade.
///  - El porcentaje de compatibilidad SOLO se muestra a quien tiene la IA Pro
///    ([showCompatibility]); para el resto no aparece.
class LikesReceivedScreen extends StatefulWidget {
  const LikesReceivedScreen({
    super.key,
    required this.currentUid,
    required this.matchService,
    required this.chatService,
    required this.summaries,
    this.canSeeAll = false,
    this.showCompatibility = false,
    this.currentUserInterests = const <String>[],
    this.onUpgrade,
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

  /// Plus/Pro ven todos los likes; Free solo una preview difuminada.
  final bool canSeeAll;

  /// Solo la IA Pro muestra el % de compatibilidad en las tarjetas.
  final bool showCompatibility;

  /// Intereses del usuario actual (para estimar afinidad real).
  final List<String> currentUserInterests;

  final VoidCallback? onUpgrade;
  final VoidCallback? onImproveProfile;

  /// Carga el perfil completo por uid para abrir el visor de SOLO LECTURA al
  /// pinchar una tarjeta (solo Plus/Pro, que sí pueden ver quién les dio like).
  final Future<SeedProfile?> Function(String uid)? loadProfile;

  /// Attra Spark (opcional). Si está habilitado, el diálogo de match ofrece
  /// "Jugar 5 minutos". Si no, se comporta igual que siempre.
  final SparkService? sparkService;
  final bool sparkEnabled;
  final String? currentUserPhotoUrl;

  /// Cuántos likes ve un usuario Free antes del muro.
  static const int freePreview = 1;

  @override
  State<LikesReceivedScreen> createState() => _LikesReceivedScreenState();
}

class _LikesReceivedScreenState extends State<LikesReceivedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  StreamSubscription<List<Like>>? _likesSub;
  StreamSubscription<List<UserMatch>>? _matchesSub;
  List<Like>? _likes;
  List<UserMatch>? _matches;
  Object? _likesError;
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
    unawaited(_likesSub?.cancel() ?? Future<void>.value());
    unawaited(_matchesSub?.cancel() ?? Future<void>.value());
    if (reset && mounted) {
      setState(() {
        _likes = null;
        _matches = null;
        _likesError = null;
        _matchesError = null;
      });
    } else {
      _likes = null;
      _matches = null;
      _likesError = null;
      _matchesError = null;
    }
    _likesSub =
        widget.matchService.observeReceivedLikes(widget.currentUid).listen(
      (List<Like> likes) {
        if (!mounted) return;
        setState(() {
          _likes = likes;
          _likesError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _likesError = error);
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
    unawaited(_likesSub?.cancel() ?? Future<void>.value());
    unawaited(_matchesSub?.cancel() ?? Future<void>.value());
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _respond(BuildContext context, Like like) async {
    try {
      final MatchFlowResult result =
          await widget.matchService.sendLike(like.fromUid);
      if (!context.mounted) return;
      if (result.isMatch) {
        final ProfileSummary other = await widget.summaries.fetch(like.fromUid);
        if (!context.mounted) return;
        final String chatId = result.chatId ?? '';
        // Si respondió con un COMENTARIO, abrimos directamente la conversación
        // para contestarle (allí ya aparece su comentario + la foto comentada).
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Like enviado!')),
        );
      }
    } on MatchServiceException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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

  /// Abre el perfil (solo lectura) de quien dio like. Solo Plus/Pro: el muro de
  /// Free no llega aquí (sus tarjetas van al paywall).
  Future<void> _openProfile(String uid) async {
    final Future<SeedProfile?> Function(String uid)? loader = widget.loadProfile;
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
      builder: (_) => ProfileViewScreen(profile: profile!),
    ));
  }

  Future<void> _discard(BuildContext context, Like like) async {
    try {
      await widget.matchService.passProfile(like.fromUid);
    } catch (_) {
      // silencioso
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
    final bool gated = !widget.canSeeAll;
    return Column(
      children: <Widget>[
        // Banner "Recibe likes en secreto" (solo Free).
        if (gated)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: _SecretLikesBanner(onUpgrade: widget.onUpgrade),
          ),
        // Pestañas.
        _LikesTabBar(controller: _tabs, mutualCount: _matches?.length ?? 0),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _likesTab(gated),
              _mutualTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Pestaña 1: quién te gusta ────────────────────────────────────────────
  Widget _likesTab(bool gated) {
    final Object? error = _likesError;
    if (error != null) {
      return _LikesLoadError(onRetry: () => _bindStreams(reset: true));
    }
    final List<Like>? currentLikes = _likes;
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
    // Free: todas las tarjetas salen difuminadas (no puede ver quién es).
    final int hidden = gated ? likes.length : 0;

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: Text(
              widget.canSeeAll
                  ? '${likes.length} ${likes.length == 1 ? "persona te ha" : "personas te han"} dado like'
                  : 'Tienes ${likes.length} ${likes.length == 1 ? "like esperando" : "likes esperando"}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
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
                      blurred: gated,
                      showCompatibility: widget.showCompatibility,
                      compatibilityOf: (ProfileSummary s) =>
                          _compatibilityPct(s, score: like.compatibilityScore),
                      onRespond: () => _respond(context, like),
                      onDiscard: () => _discard(context, like),
                      // Free → paywall. Plus/Pro → abre el perfil (si hay loader).
                      onTap: gated
                          ? widget.onUpgrade
                          : (widget.loadProfile == null
                              ? null
                              : () => _openProfile(like.fromUid)),
                    );
                  },
                  childCount: likes.length,
                ),
              );
            },
          ),
        ),
        if (gated)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: _LikesPaywall(hidden: hidden, onUpgrade: widget.onUpgrade),
            ),
          ),
        // Promo "Aumenta tus posibilidades".
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

  // ── Pestaña 2: me gustas mutuamente (matches) ────────────────────────────
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

/// Pestañas "Quién te gusta" / "Me gustas mutuamente (N)".
class _LikesTabBar extends StatelessWidget {
  const _LikesTabBar({required this.controller, required this.mutualCount});

  final TabController controller;
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
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 13 : 14.5,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: compact ? 13 : 14.5,
          ),
          dividerColor: AppColors.surfaceLine,
          tabs: <Widget>[
            const Tab(child: _TabTitle(label: 'Quién te gusta')),
            Tab(
              child: _TabTitle(
                label: compact ? 'Mutuos' : 'Me gustas mutuamente',
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

/// Banner superior "Recibe likes en secreto" (CTA a planes), solo Free.
class _SecretLikesBanner extends StatelessWidget {
  const _SecretLikesBanner({required this.onUpgrade});

  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[AppColors.wine, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: <Color>[
                AppColors.attraRed.withValues(alpha: 0.55),
                AppColors.wine.withValues(alpha: 0.2),
              ]),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Recibe likes en secreto',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Activa Likes ilimitados para descubrir a quién le gustas sin límites.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _GradientPill(label: 'Ver opciones', onTap: onUpgrade),
        ],
      ),
    );
  }
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: AppColors.action),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.attraRed.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
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
    this.blurred = false,
    this.showCompatibility = false,
    this.onTap,
  });

  final Like like;
  final ProfileSummaryRepository summaries;
  final VoidCallback onRespond;
  final VoidCallback onDiscard;
  final int? Function(ProfileSummary) compatibilityOf;
  final bool blurred;
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
        final int? pct =
            (showCompatibility && !blurred) ? compatibilityOf(s) : null;
        return _ProfileCardShell(
          photoUrl: photoTargetUrl ?? s.photoUrl,
          name: s.displayName,
          blurred: blurred,
          verified: s.verified,
          age: s.age,
          headline: s.headline,
          location: s.location,
          compatibility: pct,
          // El comentario solo se enseña a quien puede ver el like (Plus/Pro).
          comment: blurred ? null : like.commentText,
          topBadge: (action.icon, action.text, action.color),
          premiumBadge: premiumBadge,
          onTap: onTap,
          // Acciones: Free muestra "Desliza para ver"; Plus/Pro responde.
          footer: blurred
              ? const _LockedFooter()
              : _RespondFooter(onRespond: onRespond, onDiscard: onDiscard),
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
          blurred: false,
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

/// Carcasa visual compartida por las tarjetas de like y de match.
class _ProfileCardShell extends StatelessWidget {
  const _ProfileCardShell({
    required this.photoUrl,
    required this.name,
    required this.blurred,
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
  final bool blurred;
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
    final String shownName = blurred ? 'Alguien' : name;
    final String nameLine =
        (!blurred && age != null) ? '$shownName, $age' : shownName;
    final bool compactBadges = MediaQuery.sizeOf(context).width < 700;
    final String badgeText =
        compactBadges ? _compactBadgeText(topBadge.$2) : topBadge.$2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Foto (caché en disco + downscaling).
              Positioned.fill(
                child: AttraImage(url: photoUrl, fallbackInitial: name),
              ),

              // Difuminado para la preview gratuita.
              if (blurred)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(color: Colors.black.withValues(alpha: 0.25)),
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
                        if (!blurred && verified) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: AppColors.attraRed),
                        ],
                      ],
                    ),
                    if (!blurred && headline.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85))),
                    ],
                    if (!blurred && location.isNotEmpty) ...<Widget>[
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

/// Footer bloqueado para Free: "Desliza para ver" con candado.
class _LockedFooter extends StatelessWidget {
  const _LockedFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
          SizedBox(width: 6),
          Text('Desliza para ver',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Footer para Plus/Pro: botón "Responder" con degradado + descartar.
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

/// Muro para Free: hay más likes pero solo Plus/Pro los ven.
class _LikesPaywall extends StatelessWidget {
  const _LikesPaywall({required this.hidden, required this.onUpgrade});

  final int hidden;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.wine, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.lock_rounded, size: 38, color: AppColors.attraRed),
          const SizedBox(height: 10),
          Text(
            '$hidden ${hidden == 1 ? 'persona ya te ha' : 'personas ya te han'} dado like',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Hazte Attra Plus o Pro para ver quién eres y empezar a hacer match.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onUpgrade,
            icon: const Icon(Icons.workspace_premium),
            label: const Text('Ver planes'),
          ),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
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
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  'Completa tu perfil y sube más fotos para recibir más likes cada día.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary, height: 1.3),
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
                    ?.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
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
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Reintenta en unos segundos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
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
