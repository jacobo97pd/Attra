import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/app_colors.dart';
import '../data/story_service.dart';
import '../domain/story.dart';

/// Visor de stories a pantalla completa, estilo moderno (Instagram): vídeo a
/// pantalla completa con degradados, barra de progreso segmentada, cabecera con
/// autor y hora, mantener pulsado para pausar, y barra de respuesta con like,
/// Attra y texto. Registra la vista una vez; el like/Attra crea la interacción
/// (match si es recíproco) o va al chat si ya hay match.
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
  final FocusNode _replyFocus = FocusNode();
  late int _index;
  VideoPlayerController? _controller;
  bool _sending = false;
  bool _paused = false;
  String? _videoError;

  /// storyId -> 'like' | 'attra' (reacción ya enviada esta sesión).
  final Map<String, String> _reactions = <String, String>{};

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
    _replyFocus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _controller?.dispose();
    setState(() {
      _videoError = null;
      _paused = false;
    });
    final Story s = _story;
    if (!_isMine) {
      widget.storyService.viewStory(s.storyId).catchError((_) {});
    }
    if (s.videoUrl.isEmpty) {
      setState(() => _videoError = 'La story no tiene vídeo.');
      return;
    }
    final VideoPlayerController c =
        VideoPlayerController.networkUrl(Uri.parse(s.videoUrl));
    _controller = c;
    try {
      await c.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      c
        ..addListener(_onTick)
        ..setVolume(1)
        ..play();
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _videoError = 'No se pudo reproducir el vídeo.');
      }
    }
  }

  void _onTick() {
    final VideoPlayerController? c = _controller;
    if (c == null) return;
    if (c.value.isInitialized &&
        !c.value.isPlaying &&
        !_paused &&
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

  void _pause() {
    _controller?.pause();
    setState(() => _paused = true);
  }

  void _resume() {
    if (_videoError != null) return;
    _controller?.play();
    setState(() => _paused = false);
  }

  /// Like (corazón) o Attra (⭐) a la story SIN texto. Ambos registran la
  /// interacción con feedback visual; si ya hay match, va como mensaje al chat.
  Future<void> _react({required bool asAttra}) async {
    if (_sending) return;
    final String id = _story.storyId;
    setState(() {
      _sending = true;
      _reactions[id] = asAttra ? 'attra' : 'like';
    });
    try {
      final StoryReplyResult r = await widget.storyService
          .replyToStory(id, asAttra: asAttra);
      if (!mounted) return;
      _snack(switch (r.outcome) {
        'matched' => '¡Match! Ya podéis chatear 🎉',
        'message' => asAttra ? 'Enviaste un Attra ⭐' : 'Le diste like ❤️',
        _ => asAttra
            ? 'Attra enviado ⭐ Si te corresponde, haréis match.'
            : 'Like enviado ❤️ Si te corresponde, haréis match.',
      });
    } on StoryServiceException catch (e) {
      if (mounted) {
        setState(() => _reactions.remove(id));
        _snack(e.message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() async {
    final String text = _reply.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final StoryReplyResult r =
          await widget.storyService.replyToStory(_story.storyId, text: text);
      _reply.clear();
      _replyFocus.unfocus();
      if (!mounted) return;
      _snack(switch (r.outcome) {
        'matched' => '¡Match! Ya podéis chatear.',
        'message' => 'Respuesta enviada.',
        _ => 'Mensaje enviado.',
      });
    } on StoryServiceException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface,
    ));
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
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Vídeo a pantalla completa (cover) con zonas de toque.
          Positioned.fill(child: _videoLayer(c)),

          // Degradados superior e inferior para legibilidad.
          const _Scrim(alignment: Alignment.topCenter),
          const _Scrim(alignment: Alignment.bottomCenter),

          // Texto superpuesto en su posición guardada (editor tipo Instagram).
          if (_story.caption.isNotEmpty) _captionOverlay(),

          SafeArea(
            child: Column(
              children: <Widget>[
                const SizedBox(height: 6),
                _segments(progress),
                _header(),
                const Spacer(),
                if (!_isMine) _replyBar(),
              ],
            ),
          ),

          if (_paused)
            const Center(
              child: Icon(Icons.play_arrow_rounded,
                  color: Colors.white70, size: 72),
            ),
        ],
      ),
    );
  }

  Widget _videoLayer(VideoPlayerController? c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails d) {
        final double w = MediaQuery.of(context).size.width;
        if (d.globalPosition.dx < w * 0.32) {
          _prev();
        } else {
          _next();
        }
      },
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      child: _videoError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.videocam_off_outlined,
                        color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(_videoError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            )
          : (c != null && c.value.isInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white))),
    );
  }

  /// Barra de progreso segmentada (una por story del grupo).
  Widget _segments(double progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < widget.stories.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: i < _index
                        ? 1.0
                        : i == _index
                            ? progress
                            : 0.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.attraRed.withValues(alpha: 0.25),
            child: Text(
              _story.displayName.isNotEmpty
                  ? _story.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_story.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                if (_story.createdAt != null)
                  Text(_timeAgo(_story.createdAt!),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12)),
              ],
            ),
          ),
          if (_isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _confirmDelete,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// Texto en su posición normalizada (misma referencia que el editor: sobre
  /// el vídeo a pantalla completa).
  Widget _captionOverlay() {
    final Size size = MediaQuery.of(context).size;
    final double w = size.width;
    final double h = size.height;
    return Positioned(
      left: (_story.captionX * w) - w * 0.42,
      top: (_story.captionY * h) - 22,
      width: w * 0.84,
      child: IgnorePointer(
        child: Text(
          _story.caption,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            shadows: <Shadow>[
              Shadow(blurRadius: 8, color: Colors.black87),
              Shadow(blurRadius: 2, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyBar() {
    final String? reaction = _reactions[_story.storyId];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 4, 12, 10 + MediaQuery.of(context).viewInsets.bottom),
      child: Row(
        children: <Widget>[
          // Pastilla de texto glassy.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: TextField(
                controller: _reply,
                focusNode: _replyFocus,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                onTap: _pause,
                decoration: const InputDecoration(
                  hintText: 'Responder…',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _RoundBtn(
            icon: reaction == 'like'
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: AppColors.attraRed,
            active: reaction == 'like',
            onTap: _sending ? null : () => _react(asAttra: false),
          ),
          _RoundBtn(
            icon: Icons.star_rounded,
            color: AppColors.gold,
            active: reaction == 'attra',
            onTap: _sending ? null : () => _react(asAttra: true),
          ),
          _RoundBtn(
            icon: Icons.send_rounded,
            color: Colors.white,
            onTap: _sending ? null : _sendText,
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime t) {
    final Duration d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  Future<void> _confirmDelete() async {
    _pause();
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
    if (!ok) {
      _resume();
      return;
    }
    try {
      await widget.storyService.deleteStory(_story.storyId);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) _snack('No se pudo borrar la story.');
    }
  }
}

/// Degradado de legibilidad arriba/abajo.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final bool top = alignment == Alignment.topCenter;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          height: top ? 160 : 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón circular glassy de la barra de respuesta.
class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 26,
      icon: Icon(icon, color: active ? color : Colors.white),
    );
  }
}
