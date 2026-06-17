import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../data/story_service.dart';
import '../domain/story.dart';

/// Pantalla para crear una story: elegir/grabar vídeo vertical (máx 15s),
/// previsualizar, añadir caption y visibilidad, y publicar.
class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({
    super.key,
    required this.currentUid,
    required this.storyService,
  });

  final String currentUid;
  final StoryService storyService;

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  XFile? _video;
  VideoPlayerController? _preview;
  int _durationSeconds = 0;
  StoryVisibility _visibility = StoryVisibility.discovery;
  bool _publishing = false;

  @override
  void dispose() {
    _caption.dispose();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final XFile? file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 15),
    );
    if (file == null || !mounted) return;
    final VideoPlayerController controller =
        VideoPlayerController.networkUrl(Uri.parse(file.path));
    try {
      await controller.initialize();
    } catch (_) {
      // En móvil el path es local; networkUrl puede no servir para preview.
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    _preview?.dispose();
    setState(() {
      _video = file;
      _preview = controller.value.isInitialized ? controller : null;
      _durationSeconds = controller.value.isInitialized
          ? controller.value.duration.inSeconds.clamp(1, 15)
          : 10;
    });
    if (_preview != null) {
      _preview!
        ..setLooping(true)
        ..play();
    }
  }

  Future<void> _publish() async {
    final XFile? video = _video;
    if (video == null || _publishing) return;
    setState(() => _publishing = true);
    try {
      await widget.storyService.createStory(
        uid: widget.currentUid,
        video: video,
        durationSeconds: _durationSeconds <= 0 ? 10 : _durationSeconds,
        caption: _caption.text.trim(),
        visibility: _visibility,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story publicada (24h).')),
        );
        Navigator.of(context).pop();
      }
    } on StoryServiceException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('No se pudo publicar la story: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva story')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _video == null
                  ? _Picker(onGallery: () => _pick(ImageSource.gallery),
                      onCamera: () => _pick(ImageSource.camera))
                  : _Preview(controller: _preview),
            ),
            if (_video != null) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _caption,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Texto (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SegmentedButton<StoryVisibility>(
                segments: const <ButtonSegment<StoryVisibility>>[
                  ButtonSegment<StoryVisibility>(
                      value: StoryVisibility.discovery,
                      label: Text('Descubrimiento')),
                  ButtonSegment<StoryVisibility>(
                      value: StoryVisibility.matches, label: Text('Solo matches')),
                ],
                selected: <StoryVisibility>{_visibility},
                onSelectionChanged: (Set<StoryVisibility> s) =>
                    setState(() => _visibility = s.first),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload),
                label: Text(_publishing ? 'Publicando…' : 'Publicar story'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.onGallery, required this.onCamera});
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.movie_creation_outlined, size: 64),
          const SizedBox(height: 12),
          const Text('Vídeo vertical, máx 15s'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería')),
              FilledButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Grabar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.check_circle_outline, size: 48),
              SizedBox(height: 8),
              Text('Vídeo listo para publicar'),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}
