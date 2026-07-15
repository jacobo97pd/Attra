import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/app_store_validation_config.dart';
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
import '../../social/presentation/group_chat_screen.dart';
import '../data/chat_service.dart';
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
    this.dateFollowupEnabled = false,
    this.onDiscover,
    this.onOpenPlay,
  });

  /// App Store validation: lets the empty state route to Discover / Play.
  final VoidCallback? onDiscover;
  final VoidCallback? onOpenPlay;

  /// Attra Clear §1: si está activo, las conversaciones donde te toca responder
  /// se agrupan arriba en una sección "Tu turno". Default false = comportamiento
  /// idéntico al anterior.
  final bool antiGhostingEnabled;

  /// Attra Clear §3: habilita "Cerrar con elegancia" en el menú del chat.
  final bool closeGracefullyEnabled;

  /// Attra Clear §5: habilita los nudges in-chat.
  final bool nudgesEnabled;

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

  void _openStory(BuildContext context, Story story) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(
        stories: <Story>[story],
        initialIndex: 0,
        currentUid: currentUid,
        storyService: storyService!,
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
        dateFollowupEnabled: dateFollowupEnabled,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Stream de stories vivas para mostrar el aro en los avatares (map dueño->story).
    return StreamBuilder<List<Story>>(
      stream: storyService?.observeLiveStories() ??
          const Stream<List<Story>>.empty(),
      builder: (BuildContext context, AsyncSnapshot<List<Story>> storySnap) {
        final Map<String, Story> storyByOwner = <String, Story>{
          for (final Story s in storySnap.data ?? const <Story>[])
            s.ownerUid: s,
        };
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
    );
  }

  Widget _buildList(BuildContext context, Map<String, Story> storyByOwner) {
    return StreamBuilder<List<Chat>>(
      stream: chatService.observeChats(currentUid),
      builder: (BuildContext context, AsyncSnapshot<List<Chat>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Chat> all = (snapshot.data ?? <Chat>[])
            .where((Chat c) => c.status != ChatStatus.deleted)
            .toList(growable: false);
        if (all.isEmpty) {
          return _ChatsEmpty(onDiscover: onDiscover, onOpenPlay: onOpenPlay);
        }
        final List<Chat> nuevos =
            all.where((Chat c) => !_isConversation(c)).toList();
        final List<Chat> convos = all.where(_isConversation).toList();

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
            final DateTime aw = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime bw = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bw.compareTo(aw); // más reciente primero
          });
        } else {
          rest.addAll(convos);
        }

        Story? storyFor(Chat c) => storyByOwner[c.otherUid(currentUid)];

        Widget convoRow(Chat c, {bool yourTurn = false}) => _ConversationRow(
              chat: c,
              currentUid: currentUid,
              summaries: summaries,
              story: storyFor(c),
              yourTurn: yourTurn,
              waitingLabel: yourTurn && c.lastMessageAt != null
                  ? formatWaiting(now.difference(c.lastMessageAt!))
                  : null,
              onTap: () => _open(context, c),
              onOpenStory: (Story s) => _openStory(context, s),
            );

        return ListView(
          children: <Widget>[
            if (nuevos.isNotEmpty) ...<Widget>[
              const _SectionTitle('Matches nuevos'),
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: nuevos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int i) => _NewMatchAvatar(
                    chat: nuevos[i],
                    currentUid: currentUid,
                    summaries: summaries,
                    story: storyFor(nuevos[i]),
                    onTap: () => _open(context, nuevos[i]),
                    onOpenStory: (Story s) => _openStory(context, s),
                  ),
                ),
              ),
              const Divider(height: 24),
            ],
            if (antiGhostingEnabled && myTurn.isNotEmpty) ...<Widget>[
              const _SectionTitle('Tu turno'),
              ...myTurn.map((Chat c) => convoRow(c, yourTurn: true)),
              const Divider(height: 24),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
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
    final ThemeData theme = Theme.of(context);
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
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                      child: Icon(Icons.groups_rounded,
                          color: theme.colorScheme.primary),
                    ),
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
            const Divider(height: 16),
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
    this.story,
    this.onOpenStory,
  });

  final String photoUrl;
  final String name;
  final double radius;
  final Story? story;
  final void Function(Story story)? onOpenStory;

  @override
  Widget build(BuildContext context) {
    final Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0E0E0),
      backgroundImage:
          photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
      child: photoUrl.isEmpty ? Text(_initial(name)) : null,
    );
    final Story? s = story;
    if (s == null) return avatar;
    return GestureDetector(
      onTap: () => onOpenStory?.call(s),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFB8860B), Color(0xFF1D6A96)],
          ),
        ),
        child: CircleAvatar(
          radius: radius + 2,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          child: avatar,
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
    this.story,
    this.onOpenStory,
  });

  final Chat chat;
  final String currentUid;
  final ProfileSummaryRepository summaries;
  final VoidCallback onTap;
  final Story? story;
  final void Function(Story story)? onOpenStory;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(chat.otherUid(currentUid)),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary s = snap.data ?? ProfileSummary.unknown;
        return InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 72,
            child: Column(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    _RingAvatar(
                      photoUrl: s.photoUrl,
                      name: s.displayName,
                      radius: 30,
                      story: story,
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
                          child: const Icon(Icons.star,
                              size: 13, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(s.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
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
    this.story,
    this.onOpenStory,
    this.yourTurn = false,
    this.waitingLabel,
  });

  final Chat chat;
  final String currentUid;
  final ProfileSummaryRepository summaries;
  final VoidCallback onTap;
  final Story? story;
  final void Function(Story story)? onOpenStory;

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
          onTap: onTap,
          leading: _RingAvatar(
            photoUrl: s.photoUrl,
            name: s.displayName,
            radius: 26,
            story: story,
            onOpenStory: onOpenStory,
          ),
          title: Text(s.displayName,
              style: isUnread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isUnread
                      ? TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface)
                      : null),
            ],
          ),
          trailing: !isUnread
              ? null
              : unread > 0
                  // Mensajes reales sin leer: contador.
                  ? CircleAvatar(
                      radius: 11,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text('$unread',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)),
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
  const _ChatsEmpty({this.onDiscover, this.onOpenPlay});

  final VoidCallback? onDiscover;
  final VoidCallback? onOpenPlay;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // App Store validation: never a dead screen — offer guided paths.
    if (kAppStoreValidationExperience) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        children: <Widget>[
          Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text('No conversations yet. Start with a challenge',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Attra is about better conversations. Try the AI-guided flow now, '
            'explore games, or find someone to connect with.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 22),
          _EmptyAction(
            icon: Icons.psychology_alt_rounded,
            label: 'Try a Demo Challenge',
            primary: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const DemoChallengeScreen()),
            ),
          ),
          const SizedBox(height: 10),
          if (onOpenPlay != null)
            _EmptyAction(
              icon: Icons.sports_esports_rounded,
              label: 'Explore Conversation Games',
              onTap: onOpenPlay!,
            ),
          const SizedBox(height: 10),
          if (onDiscover != null)
            _EmptyAction(
              icon: Icons.explore_rounded,
              label: 'Discover People',
              onTap: onDiscover!,
            ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
    return SizedBox(
      height: 52,
      child: primary
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label))
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: theme.colorScheme.primary),
              label: Text(label)),
    );
  }
}

String _initial(String name) => name.isNotEmpty ? name[0].toUpperCase() : '?';
