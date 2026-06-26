import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/story_service.dart';
import '../domain/story.dart';

/// Visor de stories a pantalla completa. Reproduce el vídeo, registra la vista
/// (una vez), permite responder (al chat si hay match, like contextual si no) y
/// avanza entre stories.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.stories,
    required this.initialIndex,
    required this.currentUid,
    required this.storyService,
  });

  final List<Story> stories;
  final int initialIndex;
  final String currentUid;
  final StoryService storyService;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  final TextEditingController _reply = TextEditingController();
  late int _index;
  VideoPlayerController? _controller;
  bool _sending = false;
  String? _videoError;
  final Set<String> _liked = <String>{};

  Story get _story => widget.stories[_index];
  bool get _isMine => _story.ownerUid == widget.currentUid;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _controller?.dispose();
    setState(() => _videoError = null);
    final Story s = _story;
    if (!_isMine) {
      widget.storyService.viewStory(s.storyId).catchError((_) {});
    }
    if (s.videoUrl.isEmpty) {
      setState(() => _videoError = 'La story no tiene vídeo (videoUrl vacío).');
      return;
    }
    final VideoPlayerController c =
        VideoPlayerController.networkUrl(Uri.parse(s.videoUrl));
    _controller = c;
    try {
      // Timeout para no quedar en spinner infinito si el navegador no decodifica.
      await c.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      c
        ..addListener(_onTick)
        ..setVolume(1)
        ..play();
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _videoError =
            'No se pudo reproducir el vídeo en el navegador.\n$e');
      }
    }
  }

  void _onTick() {
    final VideoPlayerController? c = _controller;
    if (c == null) return;
    if (c.value.isInitialized &&
        !c.value.isPlaying &&
        c.value.position >= c.value.duration &&
        c.value.duration > Duration.zero) {
      _next();
    } else {
      setState(() {});
    }
  }

  void _next() {
    if (_index < widget.stories.length - 1) {
      setState(() => _index += 1);
      _load();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index -= 1);
      _load();
    }
  }

  /// "Me gusta" a la story: crea un like (que hace match si es recíproco) sin
  /// necesidad de escribir. Si ya hay match, va como mensaje al chat.
  Future<void> _like() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _liked.add(_story.storyId);
    });
    try {
      final StoryReplyResult r =
          await widget.storyService.replyToStory(_story.storyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (r.outcome) {
          'matched' => '¡Match! Ya podéis chatear 🎉',
          'message' => 'Le diste like a su story.',
          _ => 'Like enviado. Si te corresponde, haréis match.',
        }),
      ));
    } on StoryServiceException catch (e) {
      if (mounted) {
        setState(() => _liked.remove(_story.storyId));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send({bool asAttra = false}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final StoryReplyResult r = await widget.storyService.replyToStory(
        _story.storyId,
        text: _reply.text.trim(),
        asAttra: asAttra,
      );
      _reply.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (r.outcome) {
          'matched' => '¡Match! Ya podéis chatear.',
          'message' => 'Respuesta enviada al chat.',
          _ => asAttra ? 'Attra enviado.' : 'Like enviado.',
        }),
      ));
    } on StoryServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _controller;
    final double progress = (c != null &&
            c.value.isInitialized &&
            c.value.duration > Duration.zero)
        ? (c.value.position.inMilliseconds / c.value.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (TapUpDetails d) {
          final double w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w * 0.3) {
            _prev();
          } else {
            _next();
          }
        },
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(_story.displayName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (_isMine)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white),
                        onPressed: _confirmDelete,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: _videoError != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.videocam_off_outlined,
                                  color: Colors.white70, size: 48),
                              const SizedBox(height: 12),
                              Text(_videoError!,
                                  textAlign: TextAlign.center,
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        )
                      : (c != null && c.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: c.value.aspectRatio,
                              child: VideoPlayer(c))
                          : const CircularProgressIndicator(
                              color: Colors.white)),
                ),
              ),
              if (_story.caption.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(_story.caption,
                      style: const TextStyle(color: Colors.white)),
                ),
              if (!_isMine) _replyBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _reply,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Responder a la story…',
                  hintStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white38)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white)),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                _liked.contains(_story.storyId)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: Colors.redAccent,
              ),
              tooltip: 'Me gusta',
              onPressed: _sending ? null : _like,
            ),
            IconButton(
              icon: const Icon(Icons.star, color: Color(0xFFB8860B)),
              tooltip: 'Enviar Attra',
              onPressed: _sending ? null : () => _send(asAttra: true),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sending ? null : () => _send(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Borrar story'),
            content: const Text('Se eliminará para todos.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Borrar')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.storyService.deleteStory(_story.storyId);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo borrar la story.')),
        );
      }
    }
  }
}
