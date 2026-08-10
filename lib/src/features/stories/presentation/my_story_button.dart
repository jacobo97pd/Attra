import 'package:flutter/material.dart';

import '../data/story_service.dart';
import '../domain/story.dart';
import 'story_composer_screen.dart';
import 'story_viewer_screen.dart';

enum _MyStoryAction { view, create }

/// Punto de entrada para PUBLICAR una historia (y para repasar/borrar las
/// propias).
///
/// Existe porque el muro a ciegas se llevó por delante la tira de aros (ya
/// borrada), que era el único sitio desde el que se abría
/// [StoryComposerScreen]. Sin esto, Discover —que solo enseña a quien tiene una
/// historia viva— se vaciaba solo: a las 72 h de encender `storiesEnabled`
/// caducaba lo publicado, nadie podía publicar nada nuevo y la pantalla
/// principal quedaba muerta para todo el mundo.
class MyStoryButton extends StatefulWidget {
  const MyStoryButton({
    super.key,
    required this.currentUid,
    required this.storyService,
  });

  final String currentUid;
  final StoryService storyService;

  @override
  State<MyStoryButton> createState() => _MyStoryButtonState();
}

class _MyStoryButtonState extends State<MyStoryButton> {
  /// El stream se crea UNA vez y no en cada `build`.
  ///
  /// `observeMyLiveStories` devuelve un `Stream` nuevo en cada llamada, así que
  /// construirlo dentro de `build` hacía que `StreamBuilder` viera otro stream y
  /// cancelara y volviera a registrar el listener de Firestore. Este botón vive
  /// en la cabecera del feed, que repinta con cada snapshot del stream global de
  /// historias (basta con que alguien, en cualquier parte de la app, vea una):
  /// era un vaivén continuo de suscripciones sobre `stories` por una insignia
  /// que solo dice "3/5".
  late Stream<List<Story>> _mineStream;

  /// Último recuento bueno. Un error del stream deja el snapshot SIN datos, y
  /// entonces el botón decía "Contar algo" teniendo historias vivas: el dueño
  /// concluye que no se subió nada y vuelve a publicar. Un bache de red no puede
  /// contar como "no tienes ninguna".
  List<Story> _lastKnown = const <Story>[];

  @override
  void initState() {
    super.initState();
    _mineStream = widget.storyService.observeMyLiveStories(widget.currentUid);
  }

  @override
  void didUpdateWidget(covariant MyStoryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUid != widget.currentUid ||
        oldWidget.storyService != widget.storyService) {
      _lastKnown = const <Story>[];
      _mineStream = widget.storyService.observeMyLiveStories(widget.currentUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Story>>(
      stream: _mineStream,
      builder: (BuildContext context, AsyncSnapshot<List<Story>> snap) {
        final List<Story>? fresh = snap.data;
        if (fresh != null) _lastKnown = fresh;
        final List<Story> mine = fresh ?? _lastKnown;
        if (mine.isEmpty) {
          return TextButton.icon(
            key: const ValueKey<String>('my-story-create'),
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: const Text('Contar algo'),
          );
        }
        return Tooltip(
          message: 'Mis historias',
          child: TextButton.icon(
            key: const ValueKey<String>('my-story-menu'),
            onPressed: () => _openMenu(context, mine),
            icon: const Icon(Icons.auto_stories_rounded, size: 20),
            label: Text('${mine.length}/${StoryService.maxActiveStories}'),
          ),
        );
      },
    );
  }

  Future<void> _openMenu(BuildContext context, List<Story> mine) async {
    // El tope lo manda el servidor (MAX_ACTIVE_STORIES): aquí solo se evita
    // ofrecer una subida que se va a rechazar tras procesar y subir el vídeo.
    final bool atMax = mine.length >= StoryService.maxActiveStories;
    final _MyStoryAction? action = await showModalBottomSheet<_MyStoryAction>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Ver mis historias'),
              subtitle: Text(mine.length == 1
                  ? '1 historia viva. Puedes borrarla desde el visor.'
                  : '${mine.length} historias vivas. Puedes borrarlas desde el visor.'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MyStoryAction.view),
            ),
            ListTile(
              enabled: !atMax,
              leading: const Icon(Icons.add_a_photo_outlined),
              title: const Text('Contar algo más'),
              subtitle: atMax
                  ? const Text(
                      'Ya tienes ${StoryService.maxActiveStories} historias vivas. '
                      'Borra alguna o espera a que caduque.')
                  : null,
              onTap: atMax
                  ? null
                  : () => Navigator.of(sheetContext).pop(_MyStoryAction.create),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == _MyStoryAction.create) {
      _openCreate(context);
      return;
    }
    _openViewer(context, mine);
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryComposerScreen(
        currentUid: widget.currentUid,
        storyService: widget.storyService,
      ),
    ));
  }

  void _openViewer(BuildContext context, List<Story> mine) {
    // El visor indexa sin comprobar nada: con la lista vacía revienta al abrir.
    if (mine.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(
        stories: mine,
        initialIndex: 0,
        currentUid: widget.currentUid,
        storyService: widget.storyService,
      ),
    ));
  }
}
