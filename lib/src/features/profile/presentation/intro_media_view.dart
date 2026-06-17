import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../domain/intro_media.dart';

/// Reproductor del AUDIO de presentación de un perfil (público): botón
/// play/pausa + barra de progreso + duración. Autónomo (gestiona su propio
/// AudioPlayer y lo libera en dispose).
class IntroAudioPlayer extends StatefulWidget {
  const IntroAudioPlayer({super.key, required this.audio, this.label});

  final IntroAudio audio;

  /// Texto opcional encima (p. ej. "Audio de presentación").
  final String? label;

  @override
  State<IntroAudioPlayer> createState() => _IntroAudioPlayerState();
}

class _IntroAudioPlayerState extends State<IntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.audio.url);
      _player.playerStateStream.listen((PlayerState s) {
        if (s.processingState == ProcessingState.completed) {
          _player.pause();
          _player.seek(Duration.zero);
        }
      });
      if (mounted) setState(() => _ready = true);
    } catch (_) {/* sin sonido si falla la carga */}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final int s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration total = Duration(milliseconds: widget.audio.durationMs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (BuildContext context, AsyncSnapshot<PlayerState> snap) {
              final bool playing = snap.data?.playing ?? false;
              return InkWell(
                onTap: !_ready
                    ? null
                    : () => playing ? _player.pause() : _player.play(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.action),
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.label != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.graphic_eq_rounded,
                          size: 14, color: AppColors.attraRed),
                      const SizedBox(width: 6),
                      Text(widget.label!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder:
                      (BuildContext context, AsyncSnapshot<Duration> posSnap) {
                    final Duration pos = posSnap.data ?? Duration.zero;
                    final Duration dur = _player.duration ?? total;
                    final double value = dur.inMilliseconds == 0
                        ? 0
                        : (pos.inMilliseconds / dur.inMilliseconds)
                            .clamp(0.0, 1.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 4,
                            backgroundColor: AppColors.surfaceLine,
                            color: AppColors.attraRed,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          pos > Duration.zero ? _fmt(pos) : _fmt(dur),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reproductor del VÍDEO de presentación (público): muestra el primer frame y,
/// al tocar, reproduce en bucle con sonido. Autónomo (gestiona su controller).
class IntroVideoPlayer extends StatefulWidget {
  const IntroVideoPlayer({super.key, required this.video});

  final IntroVideo video;

  @override
  State<IntroVideoPlayer> createState() => _IntroVideoPlayerState();
}

class _IntroVideoPlayerState extends State<IntroVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final VideoPlayerController c =
        VideoPlayerController.networkUrl(Uri.parse(widget.video.url));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (mounted) setState(() => _ready = true);
    } catch (_) {/* sin vídeo si falla */}
  }

  void _toggle() {
    final VideoPlayerController? c = _controller;
    if (c == null || !_ready) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        _started = true;
        c.play();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _controller;
    final bool playing = c?.value.isPlaying ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: GestureDetector(
          onTap: _toggle,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_ready && c != null)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                )
              else
                const ColoredBox(color: AppColors.surfaceHigh),

              // Botón play/pausa superpuesto (se oculta mientras reproduce).
              if (!playing)
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 2),
                    ),
                    child: Icon(
                      _started
                          ? Icons.play_arrow_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),

              // Etiqueta.
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.videocam_rounded,
                          size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Vídeo',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
