import 'package:flutter/material.dart';

import '../../match/data/match_service.dart';
import '../../match/domain/user_match.dart';
import '../data/story_service.dart';
import '../domain/story.dart';
import 'create_story_screen.dart';
import 'story_ring.dart';
import 'story_viewer_screen.dart';

/// Barra horizontal de stories para la cabecera del feed: primero la tuya
/// (crear/ver) y luego las de tus MATCHES (solo se ven historias de personas
/// con las que hay match). Se oculta si la feature está desactivada.
class StoriesBar extends StatelessWidget {
  const StoriesBar({
    super.key,
    required this.currentUid,
    required this.currentName,
    required this.currentPhotoUrl,
    required this.storyService,
    this.matchService,
    this.excludedOwners = const <String>{},
  });

  final String currentUid;
  final String currentName;
  final String currentPhotoUrl;
  final StoryService storyService;

  /// Si se indica, solo se muestran historias de personas con las que hay
  /// match. Si es null, se muestran todas (comportamiento antiguo).
  final MatchService? matchService;
  final Set<String> excludedOwners;

  void _openViewer(BuildContext context, List<Story> stories, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(
        stories: stories,
        initialIndex: index,
        currentUid: currentUid,
        storyService: storyService,
      ),
    ));
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          CreateStoryScreen(currentUid: currentUid, storyService: storyService),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Story?>(
      stream: storyService.observeMyLiveStory(currentUid),
      builder: (BuildContext context, AsyncSnapshot<Story?> mineSnap) {
        final Story? mine = mineSnap.data;
        // Set de uids con los que hay match (para filtrar las historias). Si no
        // se pasa matchService, no se filtra (comportamiento antiguo).
        return StreamBuilder<List<UserMatch>>(
          stream: matchService?.observeMatches(currentUid) ??
              const Stream<List<UserMatch>>.empty(),
          builder: (BuildContext context,
              AsyncSnapshot<List<UserMatch>> matchSnap) {
            final Set<String> matchedUids = matchService == null
                ? const <String>{}
                : <String>{
                    for (final UserMatch m in matchSnap.data ?? <UserMatch>[])
                      m.otherUid(currentUid),
                  };
            return _buildBar(context, mine, matchedUids);
          },
        );
      },
    );
  }

  Widget _buildBar(
      BuildContext context, Story? mine, Set<String> matchedUids) {
    return StreamBuilder<List<Story>>(
          stream: storyService.observeLiveStories(
              excludeUid: currentUid, excludedOwners: excludedOwners),
          builder:
              (BuildContext context, AsyncSnapshot<List<Story>> othersSnap) {
            // Solo historias de matches (si hay matchService).
            final List<Story> others =
                (othersSnap.data ?? <Story>[]).where((Story s) {
              if (matchService == null) return true;
              return matchedUids.contains(s.ownerUid);
            }).toList(growable: false);
            return SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: <Widget>[
                  StoryRing(
                    name: currentName,
                    imageUrl: mine?.thumbnailUrl.isNotEmpty == true
                        ? mine!.thumbnailUrl
                        : currentPhotoUrl,
                    hasLiveStory: mine != null,
                    isAdd: mine == null,
                    onTap: () => mine == null
                        ? _openCreate(context)
                        : _openViewer(context, <Story>[mine], 0),
                  ),
                  const SizedBox(width: 8),
                  for (int i = 0; i < others.length; i++) ...<Widget>[
                    StoryRing(
                      name: others[i].displayName,
                      imageUrl: others[i].thumbnailUrl,
                      hasLiveStory: true,
                      onTap: () => _openViewer(context, others, i),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            );
          },
        );
  }
}
