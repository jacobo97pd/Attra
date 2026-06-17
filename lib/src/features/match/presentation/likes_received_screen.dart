import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_badges.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/presentation/chat_detail_screen.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/profile_summary.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../data/match_service.dart';
import '../domain/like.dart';
import '../domain/match_flow_result.dart';
import 'match_created_dialog.dart';

/// Bandeja de likes recibidos en GRID de fotos grandes (estilo Hinge/Bumble).
/// Cada tarjeta muestra la foto de quien te dio like, su nombre, qué hizo y las
/// acciones responder/descartar. Free ve una preview difuminada + muro.
class LikesReceivedScreen extends StatelessWidget {
  const LikesReceivedScreen({
    super.key,
    required this.currentUid,
    required this.matchService,
    required this.chatService,
    required this.summaries,
    this.canSeeAll = false,
    this.onUpgrade,
    this.sparkService,
    this.sparkEnabled = false,
  });

  final String currentUid;
  final MatchService matchService;
  final ChatService chatService;
  final ProfileSummaryRepository summaries;

  /// Plus/Pro ven todos los likes; Free solo una preview.
  final bool canSeeAll;
  final VoidCallback? onUpgrade;

  /// Attra Spark (opcional). Si está habilitado, el diálogo de match ofrece
  /// "Jugar 5 minutos". Si no, se comporta igual que siempre.
  final SparkService? sparkService;
  final bool sparkEnabled;

  /// Cuántos likes ve un usuario Free antes del muro.
  static const int freePreview = 1;

  Future<void> _respond(BuildContext context, Like like) async {
    try {
      final MatchFlowResult result = await matchService.sendLike(like.fromUid);
      if (!context.mounted) return;
      if (result.isMatch) {
        final ProfileSummary other = await summaries.fetch(like.fromUid);
        if (!context.mounted) return;
        final String chatId = result.chatId ?? '';
        await showMatchCreatedDialog(
          context,
          name: other.displayName,
          photoUrl: other.photoUrl,
          hasAttra: like.type.isAttra,
          originComment: like.commentText,
          originPhotoUrl: like.targetPhotoUrlSnapshot,
          onOpenChat: () => _openChat(context, chatId, other),
          onPlaySpark:
              (sparkEnabled && sparkService != null && chatId.isNotEmpty)
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
    final SparkService? spark = sparkService;
    if (spark == null) return;
    try {
      final String sessionId = await spark.invite(
        matchId: matchId,
        hostUid: currentUid,
        guestUid: otherUid,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SparkGameScreen(
          service: spark,
          matchId: matchId,
          sessionId: sessionId,
          currentUid: currentUid,
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
        currentUid: currentUid,
        other: other,
        chatService: chatService,
        matchService: matchService,
      ),
    ));
  }

  Future<void> _discard(BuildContext context, Like like) async {
    try {
      await matchService.passProfile(like.fromUid);
    } catch (_) {
      // silencioso
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Like>>(
      stream: matchService.observeReceivedLikes(currentUid),
      builder: (BuildContext context, AsyncSnapshot<List<Like>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.attraRed));
        }
        final List<Like> likes = snapshot.data ?? <Like>[];
        if (likes.isEmpty) {
          return const _LikesEmpty();
        }
        final bool gated = !canSeeAll && likes.length > freePreview;
        final int visible = gated ? freePreview : likes.length;
        final int hidden = likes.length - visible;

        return CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: Text(
                  canSeeAll
                      ? '${likes.length} ${likes.length == 1 ? "persona" : "personas"} te han dado like'
                      : 'Tienes likes esperando',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    // En la preview gratuita, difuminamos para incitar al upgrade.
                    final bool blurred = gated;
                    return _LikeGridCard(
                      like: likes[i],
                      summaries: summaries,
                      blurred: blurred,
                      onRespond: () => _respond(context, likes[i]),
                      onDiscard: () => _discard(context, likes[i]),
                      onTap: blurred ? onUpgrade : null,
                    );
                  },
                  childCount: visible,
                ),
              ),
            ),
            if (gated)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                sliver: SliverToBoxAdapter(
                  child: _LikesPaywall(hidden: hidden, onUpgrade: onUpgrade),
                ),
              ),
          ],
        );
      },
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
    this.blurred = false,
    this.onTap,
  });

  final Like like;
  final ProfileSummaryRepository summaries;
  final VoidCallback onRespond;
  final VoidCallback onDiscard;
  final bool blurred;
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
    final ThemeData theme = Theme.of(context);
    final ({IconData icon, String text, Color color}) action = _action;
    final AttraBadgeKind? premiumBadge = like.type.isAttra
        ? null
        : like.senderIsPro
            ? AttraBadgeKind.pro
            : like.senderIsPlus
                ? AttraBadgeKind.plus
                : null;
    // Si el like fue a una foto concreta, mostramos esa foto; si no, la de perfil.
    final String? photoTargetUrl =
        like.isPhotoTarget ? like.targetPhotoUrlSnapshot : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: FutureBuilder<ProfileSummary>(
            future: summaries.fetch(like.fromUid),
            builder:
                (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
              final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
              final String url = photoTargetUrl ?? s.photoUrl;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Foto.
                  if (url.isNotEmpty)
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                          _Fallback(name: s.displayName),
                    )
                  else
                    _Fallback(name: s.displayName),

                  // Difuminado para la preview gratuita.
                  if (blurred)
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child:
                          Container(color: Colors.black.withValues(alpha: 0.2)),
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
                        stops: <double>[0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  // Badge de tipo (arriba izquierda).
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusPill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(action.icon, size: 13, color: action.color),
                              const SizedBox(width: 4),
                              Text(
                                action.text,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        if (premiumBadge != null) ...<Widget>[
                          const SizedBox(height: 6),
                          AttraPremiumBadge(premiumBadge, compact: true),
                        ],
                      ],
                    ),
                  ),

                  // Descartar (arriba derecha).
                  if (!blurred)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _MiniCircleButton(
                        icon: Icons.close_rounded,
                        onPressed: onDiscard,
                      ),
                    ),

                  // Nombre + botón responder (abajo).
                  Positioned(
                    left: 12,
                    right: 10,
                    bottom: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            blurred ? 'Alguien' : s.displayName,
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
                        if (!blurred)
                          _RespondButton(onPressed: onRespond)
                        else
                          const Icon(Icons.lock_rounded,
                              color: Colors.white70, size: 20),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Botón circular pequeño semitransparente (descartar).
class _MiniCircleButton extends StatelessWidget {
  const _MiniCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Botón circular principal (responder) con degradado de marca.
class _RespondButton extends StatelessWidget {
  const _RespondButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: AppColors.action),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.attraRed.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child:
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Placeholder cuando no hay foto: inicial sobre grafito.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 48,
            fontWeight: FontWeight.w700),
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
          const Icon(Icons.favorite, size: 40, color: AppColors.attraRed),
          const SizedBox(height: 10),
          Text(
            '$hidden ${hidden == 1 ? 'persona más' : 'personas más'} te han dado like',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Hazte Attra Plus para ver todos tus likes en grande y hacer match.',
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

class _LikesEmpty extends StatelessWidget {
  const _LikesEmpty();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.favorite_border,
                size: 56, color: AppColors.attraRed),
            const SizedBox(height: 16),
            Text('Sin likes todavía',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('Cuando alguien te dé like, aparecerá aquí en grande.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
