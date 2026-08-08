import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../domain/story.dart';
import '../domain/story_composer.dart';

/// Confirmación antes de publicar.
///
/// El compositor publicaba en cuanto tocabas una miniatura de la cuadrícula: el
/// MISMO gesto que harías solo para verla más grande. Una historia es pública y
/// dura 72 h, así que un toque de más la sacaba a la calle sin vuelta atrás.
/// Al retirar el editor se fue con él este paso, que no era edición.
///
/// Devuelve `true` por Navigator si se confirma; `null`/`false` si se descarta.
class StoryPreviewScreen extends StatefulWidget {
  const StoryPreviewScreen({
    super.key,
    required this.draft,
    this.imageBuilder,
  });

  final StoryDraft draft;

  /// Cómo pintar la foto. Existe para los tests: `Image.file` necesita un
  /// fichero real en disco y en un widget test no hay ninguno.
  final Widget Function(File file)? imageBuilder;

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  VideoPlayerController? _video;

  bool get _isVideo => widget.draft.type == StoryMediaType.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _prepareVideo();
  }

  Future<void> _prepareVideo() async {
    final VideoPlayerController controller =
        VideoPlayerController.file(File(widget.draft.file.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      // Si el vídeo no se puede previsualizar NO se bloquea la publicación: se
      // enseña el fondo y el botón. Impedir publicar por un fallo del
      // reproductor sería castigar a quien no ha hecho nada mal.
      await controller.dispose();
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _video = controller);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? video = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_isVideo)
            if (video != null)
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              )
            else
              const SizedBox.shrink()
          else
            (widget.imageBuilder ?? _defaultImage)(File(widget.draft.file.path)),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                key: const Key('story-preview-back'),
                tooltip: 'Elegir otra',
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('story-preview-publish'),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Publicar historia'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _defaultImage(File file) =>
      Image.file(file, fit: BoxFit.contain);
}
