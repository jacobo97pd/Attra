import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../match/data/match_service.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_summary.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../spark/data/spark_service.dart';
import '../../stories/data/story_service.dart';
import '../../stories/domain/story.dart';
import '../../stories/presentation/story_viewer_screen.dart';
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
  });

  final String currentUid;
  final ChatService chatService;
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
      c.lastMessageType == MessageType.twoTruths;

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
          return const _ChatsEmpty();
        }
        final List<Chat> nuevos =
            all.where((Chat c) => !_isConversation(c)).toList();
        final List<Chat> convos = all.where(_isConversation).toList();

        Story? storyFor(Chat c) => storyByOwner[c.otherUid(currentUid)];

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
            const _SectionTitle('Conversaciones'),
            if (convos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cuando escribas a un match, la conversación aparecerá aquí.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...convos.map((Chat c) => _ConversationRow(
                    chat: c,
                    currentUid: currentUid,
                    summaries: summaries,
                    story: storyFor(c),
                    onTap: () => _open(context, c),
                    onOpenStory: (Story s) => _openStory(context, s),
                  )),
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
  });

  final Chat chat;
  final String currentUid;
  final ProfileSummaryRepository summaries;
  final VoidCallback onTap;
  final Story? story;
  final void Function(Story story)? onOpenStory;

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
          subtitle: Text(chat.lastMessage ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isUnread
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface)
                  : null),
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
  const _ChatsEmpty();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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

String _initial(String name) => name.isNotEmpty ? name[0].toUpperCase() : '?';
