import 'package:flutter/material.dart';

import '../data/story_service.dart';
import '../domain/story.dart';
import 'create_story_screen.dart';
import 'story_ring.dart';
import 'story_viewer_screen.dart';

/// Barra horizontal de stories para la cabecera del feed: primero la tuya
/// (crear/ver) y luego las de los demás (vivas). Se oculta si la feature está
/// desactivada o no hay stories.
class StoriesBar extends StatelessWidget {
  const StoriesBar({
    super.key,
    required this.currentUid,
    required this.currentName,
    required this.currentPhotoUrl,
    required this.storyService,
    this.excludedOwners = const <String>{},
  });

  final String currentUid;
  final String currentName;
  final String currentPhotoUrl;
  final StoryService storyService;
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
        return StreamBuilder<List<Story>>(
          stream: storyService.observeLiveStories(
              excludeUid: currentUid, excludedOwners: excludedOwners),
          builder:
              (BuildContext context, AsyncSnapshot<List<Story>> othersSnap) {
            final List<Story> others = othersSnap.data ?? <Story>[];
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
      },
    );
  }
}
