import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_store_validation_config.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_editorial.dart';
import '../../connection_lab/presentation/conversation_games_screen.dart';
import '../../connection_lab/presentation/demo_challenge_screen.dart';
import '../../match/data/match_service.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_summary.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../spark/data/spark_service.dart';
import '../../stories/data/story_service.dart';
import '../../stories/domain/story.dart';
import '../../stories/presentation/story_viewer_screen.dart';
import '../../anti_ghosting/domain/conversation_turn.dart';
import '../../anti_ghosting/presentation/your_turn_badge.dart';
import '../../date_plans/data/date_plan_service.dart';
import '../../safedate/data/safedate_service.dart';
import '../../social/data/friend_group_service.dart';
import '../../social/domain/friend_group.dart';
import '../../social/presentation/group_avatar.dart';
import '../../social/presentation/group_chat_screen.dart';
import '../data/chat_service.dart';
import '../data/reply_suggestion_service.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';
import 'chat_detail_screen.dart';

/// Seccion "Chats": arriba los matches nuevos (sin conversacion de texto aun),
/// abajo las conversaciones activas ordenadas por ultimo mensaje.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({
    super.key,
    required this.currentUid,
    required this.chatService,
    this.datePlanService,
    this.datePlansEnabled = false,
    this.safeDateService,
    this.safeDatePlanEnabled = false,
    this.safeDateAiRiskEnabled = false,
    this.safeDateSafePlacesEnabled = false,
    this.friendGroupService,
    this.currentUserName = '',
    required this.matchService,
    required this.summaries,
    this.storyService,
    this.loadProfile,
    this.sparkService,
    this.sparkEnabled = false,
    this.metrics,
    this.journeyEnabled = false,
    this.icebreakersEnabled = false,
    this.dateBuilderEnabled = false,
    this.dateBuilderFull = false,
    this.thisOrThatEnabled = false,
    this.doubleAnswerEnabled = false,
    this.twoTruthsEnabled = false,
    this.matchReactivationEnabled = false,
    this.chatGameEnabled = false,
    this.antiGhostingEnabled = false,
    this.closeGracefullyEnabled = false,
    this.nudgesEnabled = false,
    this.replySuggestionService,
    this.replySuggestionsEnabled = false,
    this.onRequestSuggestionConsent,
    this.dateFollowupEnabled = false,
    this.onDiscover,
    this.onOpenPlay,
    this.onOpenUpgrade,
  });

  /// Abre el paywall. Se usa cuando el backend rechaza un minijuego por el
  /// límite diario del plan Free: antes eso salía como un error genérico y
  /// parecía que el juego estaba roto.
  final VoidCallback? onOpenUpgrade;

  /// App Store validation: lets the empty state route to Discover / Play.
  final VoidCallback? onDiscover;

  /// Entrada al hub de juegos desde la navegación principal. Qué fallaba: el
  /// contenedor dejó de pasarla, así que el único acceso al hub desaparecía y
  /// los juegos parecían no existir. Ahora es opcional: si no llega, la pantalla
  /// abre el hub ella misma con una ruta propia.
  final VoidCallback? onOpenPlay;

  /// Attra Clear §1: si está activo, las conversaciones donde te toca responder
  /// se agrupan arriba en una sección "Tu turno". Default false = comportamiento
  /// idéntico al anterior.
  final bool antiGhostingEnabled;

  /// Attra Clear §3: habilita "Cerrar con elegancia" en el menú del chat.
  final bool closeGracefullyEnabled;

  /// Attra Clear §5: habilita los nudges in-chat.
  final bool nudgesEnabled;

  /// Sugerencias de respuesta en el chat (Pro + consentimiento + flag).
  final ReplySuggestionService? replySuggestionService;
  final bool replySuggestionsEnabled;
  final VoidCallback? onRequestSuggestionConsent;

  /// Attra Clear §6: habilita el follow-up post-cita.
  final bool dateFollowupEnabled;

  final String currentUid;
  final ChatService chatService;

  /// Attra Plans: propuestas de cita. Opt-in por flag; requiere el servicio.
  final DatePlanService? datePlanService;
  final bool datePlansEnabled;

  /// Attra SafeDate: "Planear cita segura" + "Revisar seguridad" en el menú del
  /// chat. Opt-in por flags.
  final SafeDateService? safeDateService;
  final bool safeDatePlanEnabled;
  final bool safeDateAiRiskEnabled;
  final bool safeDateSafePlacesEnabled;

  /// Modo Amigos: chats de grupo en un apartado "Planes y grupos".
  final FriendGroupService? friendGroupService;
  final String currentUserName;

  final MatchService matchService;
  final ProfileSummaryRepository summaries;
  final StoryService? storyService;
  final Future<SeedProfile?> Function(String uid)? loadProfile;
  final SparkService? sparkService;
  final bool sparkEnabled;
  final FeedMetricsService? metrics;
  final bool journeyEnabled;
  final bool icebreakersEnabled;
  final bool dateBuilderEnabled;
  final bool dateBuilderFull;
  final bool thisOrThatEnabled;
  final bool doubleAnswerEnabled;
  final bool twoTruthsEnabled;
  final bool matchReactivationEnabled;
  final bool chatGameEnabled;

  /// Abre el hub de juegos. Usa el callback del contenedor si existe y, si no,
  /// empuja la pantalla directamente: así la entrada nunca vuelve a quedar
  /// inalcanzable por un cambio en la navegación principal.
  void _openPlay(BuildContext context) {
    final VoidCallback? external = onOpenPlay;
    if (external != null) {
      external();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConversationGamesScreen(
        onDiscover: onDiscover == null
            ? null
            : () {
                Navigator.of(context).maybePop();
                onDiscover!();
              },
      ),
    ));
  }

  void _openStory(BuildContext context, List<Story> stories) {
    // Se pasa el GRUPO entero. Antes se abria con `<Story>[story]`: el visor
    // pintaba una sola barra de segmento y el primer toque a la derecha cerraba
    // la pantalla, asi que del match solo se veia una historia y las demas eran
    // inalcanzables desde Chats.
    if (stories.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(
        stories: stories,
        initialIndex: 0,
        currentUid: currentUid,
        storyService: storyService!,
        matchService: matchService,
      ),
    ));
  }

  /// Una conversacion "real" (texto, media o propuesta de cita). Los matches cuyo
  /// ultimo mensaje es solo el contexto de apertura siguen en "Matches nuevos".
  bool _isConversation(Chat c) =>
      c.lastMessageType == MessageType.text ||
      c.lastMessageType == MessageType.dateProposal ||
      c.lastMessageType == MessageType.image ||
      c.lastMessageType == MessageType.bombImage ||
      c.lastMessageType == MessageType.voiceNote ||
      c.lastMessageType == MessageType.system ||
      c.lastMessageType == MessageType.doubleAnswer ||
      c.lastMessageType == MessageType.twoTruths ||
      c.lastMessageType == MessageType.closure;

  Future<void> _open(BuildContext context, Chat chat) async {
    final ProfileSummary other =
        await summaries.fetch(chat.otherUid(currentUid));
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatDetailScreen(
        chatId: chat.id,
        currentUid: currentUid,
        other: other,
        chatService: chatService,
        datePlanService: datePlanService,
        datePlansEnabled: datePlansEnabled,
        safeDateService: safeDateService,
        safeDatePlanEnabled: safeDatePlanEnabled,
        safeDateAiRiskEnabled: safeDateAiRiskEnabled,
        safeDateSafePlacesEnabled: safeDateSafePlacesEnabled,
        matchService: matchService,
        loadProfile: loadProfile,
        sparkService: sparkService,
        sparkEnabled: sparkEnabled,
        metrics: metrics,
        journeyEnabled: journeyEnabled,
        icebreakersEnabled: icebreakersEnabled,
        dateBuilderEnabled: dateBuilderEnabled,
        dateBuilderFull: dateBuilderFull,
        thisOrThatEnabled: thisOrThatEnabled,
        doubleAnswerEnabled: doubleAnswerEnabled,
        twoTruthsEnabled: twoTruthsEnabled,
        matchReactivationEnabled: matchReactivationEnabled,
        chatGameEnabled: chatGameEnabled,
        closeGracefullyEnabled: closeGracefullyEnabled,
        nudgesEnabled: nudgesEnabled,
        replySuggestionService: replySuggestionService,
        replySuggestionsEnabled: replySuggestionsEnabled,
        onRequestSuggestionConsent: onRequestSuggestionConsent,
        dateFollowupEnabled: dateFollowupEnabled,
        onOpenUpgrade: onOpenUpgrade,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Stream de stories vivas para mostrar el aro en los avatares (map dueño->story).
    return AttraContentFrame(
      child: StreamBuilder<Map<String, List<Story>>>(
        stream: storyService?.observeLiveStoriesForMatches() ??
            const Stream<Map<String, List<Story>>>.empty(),
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, List<Story>>> storySnap,
        ) {
          final Map<String, List<Story>> storyByOwner =
              storySnap.data ?? const <String, List<Story>>{};
          // "Planes y grupos": chats de grupo arriba (si hay). Se rinde solo si no
          // hay grupos. El resto de la pantalla (matches/conversaciones) va debajo.
          if (friendGroupService != null && currentUid.isNotEmpty) {
            return Column(
              children: <Widget>[
                _GroupsChatSection(
                  uid: currentUid,
                  userName: currentUserName,
                  service: friendGroupService!,
                ),
                Expanded(child: _buildList(context, storyByOwner)),
              ],
            );
          }
          return _buildList(context, storyByOwner);
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    Map<String, List<Story>> storyByOwner,
  ) {
    return _ChatsStreamView(
      chatService: chatService,
      currentUid: currentUid,
      builder: (BuildContext context, AsyncSnapshot<List<Chat>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // Bloqueados y matches deshechos fuera, para los dos (ver
        // Chat.isListed). El repositorio ya los quita; se repite aquí porque
        // la pantalla no debe depender de qué stream le pasen.
        final List<Chat> all = (snapshot.data ?? <Chat>[])
            .where((Chat c) => c.isListed)
            .toList(growable: false);
        if (all.isEmpty) {
          return _ChatsEmpty(
            onDiscover: onDiscover,
            onOpenPlay: () => _openPlay(context),
          );
        }
        // "Matches nuevos" es solo para matches VIVOS. Un chat cerrado que se
        // lista (cierre con elegancia) es historia: va a "Conversaciones",
        // archivado y de solo lectura, nunca como "match nuevo".
        final List<Chat> nuevos = all
            .where((Chat c) => c.status.isActive && !_isConversation(c))
            .toList();
        final List<Chat> convos = all
            .where((Chat c) => !c.status.isActive || _isConversation(c))
            .toList();

        // Attra Clear §1: separa las conversaciones donde TE TOCA responder.
        // Orden: "Tu turno" por más antiguo esperando primero; el resto por
        // último mensaje más reciente. Si el flag está off, no se altera nada.
        final DateTime now = DateTime.now();
        final List<Chat> myTurn = <Chat>[];
        final List<Chat> rest = <Chat>[];
        if (antiGhostingEnabled) {
          for (final Chat c in convos) {
            (c.isMyTurn(currentUid) ? myTurn : rest).add(c);
          }
          myTurn.sort((Chat a, Chat b) {
            final DateTime aw = a.lastMessageAt ?? now;
            final DateTime bw = b.lastMessageAt ?? now;
            return aw.compareTo(bw); // más antiguo esperando primero
          });
          rest.sort((Chat a, Chat b) {
            final DateTime aw =
                a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime bw =
                b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bw.compareTo(aw); // más reciente primero
          });
        } else {
          rest.addAll(convos);
        }

        List<Story>? storyFor(Chat c) => storyByOwner[c.otherUid(currentUid)];

        Widget convoRow(Chat c, {bool yourTurn = false}) => _ConversationRow(
              chat: c,
              currentUid: currentUid,
              summaries: summaries,
              stories: storyFor(c),
              yourTurn: yourTurn,
              waitingLabel: yourTurn && c.lastMessageAt != null
                  ? formatWaiting(now.difference(c.lastMessageAt!))
                  : null,
              onTap: () => _open(context, c),
              onOpenStory: (List<Story> group) => _openStory(context, group),
            );

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: <Widget>[
            // Entrada al hub de juegos. Antes solo existía en el estado vacío
            // de Chats y ni siquiera se pintaba, porque el callback que la
            // activaba dejó de pasarse: el hub con los cinco juegos quedó
            // inalcanzable. `_openPlay` siempre tiene salida (usa el callback
            // externo si llega y, si no, abre la pantalla directamente), así
            // que la banda nunca lleva a un callejón sin salida.
            _PlayHubEntry(onTap: () => _openPlay(context)),
            if (nuevos.isNotEmpty) ...<Widget>[
              const _SectionTitle('Matches nuevos'),
              SizedBox(
                height: 88 + MediaQuery.textScalerOf(context).scale(13) * 1.4,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageInset(context)),
                  itemCount: nuevos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int i) => _NewMatchAvatar(
                    chat: nuevos[i],
                    currentUid: currentUid,
                    summaries: summaries,
                    stories: storyFor(nuevos[i]),
                    onTap: () => _open(context, nuevos[i]),
                    onOpenStory: (List<Story> group) =>
                        _openStory(context, group),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (antiGhostingEnabled && myTurn.isNotEmpty) ...<Widget>[
              const _SectionTitle('Tu turno'),
              ...myTurn.map((Chat c) => convoRow(c, yourTurn: true)),
              const SizedBox(height: AppSpacing.md),
            ],
            const _SectionTitle('Conversaciones'),
            if (rest.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  antiGhostingEnabled && myTurn.isNotEmpty
                      ? 'No tienes otras conversaciones activas ahora mismo.'
                      : 'Cuando escribas a un match, la conversación aparecerá aquí.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...rest.map((Chat c) => convoRow(c)),
          ],
        );
      },
    );
  }
}

class _ChatsStreamView extends StatefulWidget {
  const _ChatsStreamView({
    required this.chatService,
    required this.currentUid,
    required this.builder,
  });

  final ChatService chatService;
  final String currentUid;
  final AsyncWidgetBuilder<List<Chat>> builder;

  @override
  State<_ChatsStreamView> createState() => _ChatsStreamViewState();
}

class _ChatsStreamViewState extends State<_ChatsStreamView> {
  late Stream<List<Chat>> _stream;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _stream = widget.chatService.observeChats(widget.currentUid);
  }

  @override
  void didUpdateWidget(covariant _ChatsStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatService != widget.chatService ||
        oldWidget.currentUid != widget.currentUid) {
      _stream = widget.chatService.observeChats(widget.currentUid);
      _attempt++;
    }
  }

  void _retry() {
    setState(() {
      _stream = widget.chatService.observeChats(widget.currentUid);
      _attempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Chat>>(
      key: ValueKey<int>(_attempt),
      stream: _stream,
      builder: (BuildContext context, AsyncSnapshot<List<Chat>> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.cloud_off_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text('No se pudieron cargar tus conversaciones.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }
        return widget.builder(context, snapshot);
      },
    );
  }
}

/// Banda de acceso al hub de juegos, siempre visible sobre la lista de chats.
class _PlayHubEntry extends StatelessWidget {
  const _PlayHubEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pageInset(context),
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      leading: Icon(Icons.sports_esports_outlined,
          size: 22, color: context.colors.textSecondary),
      title: Text('Juegos de conversación', style: theme.textTheme.titleSmall),
      subtitle: Text('Duelo de Química, Spark, Dos verdades y más',
          style: theme.textTheme.bodySmall),
      trailing: Icon(Icons.chevron_right_rounded,
          color: context.colors.textSecondary),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.pageInset(context), AppSpacing.xl,
          AppSpacing.pageInset(context), AppSpacing.md),
      child: AttraSectionHeading(title: text),
    );
  }
}

/// Apartado "Planes y grupos": lista los grupos del usuario; cada uno abre su
/// chat de grupo. Se rinde vacío (nada) si el usuario no está en ningún grupo.
class _GroupsChatSection extends StatelessWidget {
  const _GroupsChatSection({
    required this.uid,
    required this.userName,
    required this.service,
  });

  final String uid;
  final String userName;
  final FriendGroupService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendGroup>>(
      stream: service.observeMyGroups(uid),
      builder: (BuildContext context, AsyncSnapshot<List<FriendGroup>> snap) {
        final List<FriendGroup> groups = snap.data ?? const <FriendGroup>[];
        if (groups.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionTitle('Planes y grupos'),
            // Acotado: si hay muchos grupos, la lista tiene su propio scroll y no
            // empuja las conversaciones fuera de la pantalla.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 244),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: groups.length,
                itemBuilder: (BuildContext context, int i) {
                  final FriendGroup g = groups[i];
                  return ListTile(
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.pageInset(context),
                        vertical: AppSpacing.sm),
                    leading: GroupAvatar(
                        photoUrl: g.photoUrl, size: 44, circle: true),
                    title: Text(g.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      <String>[
                        if (g.city.isNotEmpty) g.city,
                        '${g.memberCount} miembros',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GroupChatScreen(
                          groupId: g.id,
                          groupName: g.name,
                          groupPhotoUrl: g.photoUrl,
                          currentUid: uid,
                          currentUserName: userName,
                          service: service,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        );
      },
    );
  }
}

/// Avatar circular con aro de story (degradado) si [story] != null. Tocar el
/// aro abre la story; tocar fuera deja pasar el gesto al padre (abrir chat).
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({
    required this.photoUrl,
    required this.name,
    required this.radius,
    this.stories,
    this.onOpenStory,
  });

  final String photoUrl;
  final String name;
  final double radius;

  /// Grupo completo de historias vivas de esa persona (puede tener hasta 5).
  final List<Story>? stories;
  final void Function(List<Story> stories)? onOpenStory;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.surfaceHigh,
      foregroundColor: context.colors.textPrimary,
      backgroundImage:
          photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
      child: photoUrl.isEmpty ? Text(_initial(name)) : null,
    );
    final List<Story>? group = stories;
    if (group == null || group.isEmpty) return avatar;
    return Semantics(
      button: true,
      label: 'Ver historias de $name',
      excludeSemantics: true,
      onTap: onOpenStory == null ? null : () => onOpenStory!(group),
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: () => onOpenStory?.call(group),
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
          ),
          child: CircleAvatar(
            radius: radius + 2,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            child: avatar,
          ),
        ),
      ),
    );
  }
}

class _NewMatchAvatar extends StatelessWidget {
  const _NewMatchAvatar({
    required this.chat,
    required this.currentUid,
    required this.summaries,
    required this.onTap,
    this.stories,
    this.onOpenStory,
  });

  final Chat chat;
  final String currentUid;
  final ProfileSummaryRepository summaries;
  final VoidCallback onTap;

  /// Grupo completo de historias vivas de esa persona (puede tener hasta 5).
  final List<Story>? stories;
  final void Function(List<Story> stories)? onOpenStory;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(chat.otherUid(currentUid)),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
        return InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 92,
            child: Column(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    _RingAvatar(
                      photoUrl: s.photoUrl,
                      name: s.displayName,
                      radius: 30,
                      stories: stories,
                      onOpenStory: onOpenStory,
                    ),
                    if (chat.hasAttra)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(Icons.star,
                              size: 13,
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(s.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.chat,
    required this.currentUid,
    required this.summaries,
    required this.onTap,
    this.stories,
    this.onOpenStory,
    this.yourTurn = false,
    this.waitingLabel,
  });

  final Chat chat;
  final String currentUid;
  final ProfileSummaryRepository summaries;
  final VoidCallback onTap;

  /// Grupo completo de historias vivas de esa persona (puede tener hasta 5).
  final List<Story>? stories;
  final void Function(List<Story> stories)? onOpenStory;

  /// Attra Clear §1: fila de la sección "Tu turno" (muestra el badge).
  final bool yourTurn;
  final String? waitingLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int unread = chat.unreadFor(currentUid);
    final bool isUnread = chat.isUnreadFor(currentUid);
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(chat.otherUid(currentUid)),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
        return ListTile(
          contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pageInset(context),
              vertical: AppSpacing.sm),
          onTap: onTap,
          leading: _RingAvatar(
            photoUrl: s.photoUrl,
            name: s.displayName,
            radius: 26,
            stories: stories,
            onOpenStory: onOpenStory,
          ),
          title: Text(s.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (yourTurn) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: YourTurnBadge(waitingLabel: waitingLabel),
                ),
                const SizedBox(height: 3),
              ],
              Text(chat.lastMessage ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isUnread ? FontWeight.w500 : FontWeight.w400,
                    color: isUnread
                        ? context.colors.textPrimary
                        : context.colors.textSecondary,
                  )),
            ],
          ),
          trailing: !isUnread
              ? null
              : unread > 0
                  // Mensajes reales sin leer: contador.
                  ? CircleAvatar(
                      radius: 6 +
                          MediaQuery.textScalerOf(context).scale(13) *
                              unread.toString().length /
                              2,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text('$unread',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onPrimary)),
                    )
                  // Marcado manualmente como no leido: punto.
                  : CircleAvatar(
                      radius: 6, backgroundColor: theme.colorScheme.primary),
        );
      },
    );
  }
}

class _ChatsEmpty extends StatelessWidget {
  const _ChatsEmpty({this.onDiscover, required this.onOpenPlay});

  final VoidCallback? onDiscover;

  /// Ya no es opcional: el botón "Explorar juegos" nunca llegaba a pintarse
  /// porque el callback venía siempre a null desde el contenedor.
  final VoidCallback onOpenPlay;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Que la pantalla no se quede muerta: se ofrecen caminos guiados.
    // Los textos van en castellano como el resto de la app; estaban en
    // ingles y se colaban tal cual en una interfaz en castellano.
    if (kAppStoreValidationExperience) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        children: <Widget>[
          Icon(Icons.auto_awesome, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text('Aún no hay conversaciones. Empieza por un reto',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Attra va de conversaciones mejores. Prueba el reto guiado, '
            'echa un vistazo a los juegos o busca a alguien con quien hablar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          _EmptyAction(
            icon: Icons.psychology_alt_rounded,
            label: 'Probar un reto de ejemplo',
            primary: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const DemoChallengeScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _EmptyAction(
            icon: Icons.sports_esports_rounded,
            label: 'Ver los juegos de conversación',
            onTap: onOpenPlay,
          ),
          const SizedBox(height: 10),
          if (onDiscover != null)
            _EmptyAction(
              icon: Icons.explore_rounded,
              label: 'Descubrir personas',
              onTap: onDiscover!,
            ),
        ],
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.pageInset(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.forum_outlined,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Aún no tienes matches', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Cuando hagas match, podrás empezar a chatear aquí.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Esta rama tampoco ofrecía los juegos por ningún lado.
            _EmptyAction(
              icon: Icons.sports_esports_rounded,
              label: 'Ver los juegos de conversación',
              onTap: onOpenPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAction extends StatelessWidget {
  const _EmptyAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
      child: primary
          ? FilledButton.icon(
              onPressed: onTap, icon: Icon(icon), label: Text(label))
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: theme.colorScheme.primary),
              label: Text(label)),
    );
  }
}

String _initial(String name) => name.isNotEmpty ? name[0].toUpperCase() : '?';
