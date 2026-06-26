import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/chat_message.dart';

/// Reproductor unico de notas de voz: garantiza que solo suena UN audio a la
/// vez. La pantalla de chat crea uno y lo comparte entre todas las burbujas;
/// al salir del chat se hace dispose (detiene la reproduccion).
class VoiceNotePlayerController {
  VoiceNotePlayerController() {
    _player.playerStateStream.listen((PlayerState s) {
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  String? _currentUrl;

  String? get currentUrl => _currentUrl;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration? get duration => _player.duration;

  bool isCurrent(String url) => _currentUrl == url;

  /// Play/pausa para una URL. Si era otra, cambia de pista (detiene la anterior).
  Future<void> toggle(String url) async {
    if (_currentUrl == url) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    _currentUrl = url;
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      _currentUrl = null;
    }
  }

  Future<void> stop() async {
    _currentUrl = null;
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}

/// Burbuja de nota de voz: play/pausa + barra de progreso + duracion.
class VoiceNoteBubble extends StatelessWidget {
  const VoiceNoteBubble({
    super.key,
    required this.media,
    required this.mine,
    required this.controller,
  });

  final MediaInfo media;
  final bool mine;
  final VoiceNotePlayerController controller;

  String _fmt(Duration d) {
    final int s = d.inSeconds;
    return '${(s ~/ 60).toString().padLeft(1, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg =
        mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final Duration total = Duration(milliseconds: media.durationMs ?? 0);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: StreamBuilder<PlayerState>(
          stream: controller.playerStateStream,
          builder:
              (BuildContext context, AsyncSnapshot<PlayerState> stateSnap) {
            final bool isCurrent = controller.isCurrent(media.downloadUrl);
            final bool playing =
                isCurrent && (stateSnap.data?.playing ?? false);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  color: fg,
                  icon: Icon(playing ? Icons.pause_circle : Icons.play_circle,
                      size: 34),
                  onPressed: () => controller.toggle(media.downloadUrl),
                ),
                const SizedBox(width: 4),
                StreamBuilder<Duration>(
                  stream: controller.positionStream,
                  builder:
                      (BuildContext context, AsyncSnapshot<Duration> posSnap) {
                    final Duration pos = isCurrent
                        ? (posSnap.data ?? Duration.zero)
                        : Duration.zero;
                    final Duration dur =
                        isCurrent ? (controller.duration ?? total) : total;
                    final double value = dur.inMilliseconds == 0
                        ? 0
                        : (pos.inMilliseconds / dur.inMilliseconds)
                            .clamp(0.0, 1.0);
                    return SizedBox(
                      width: 130,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          LinearProgressIndicator(
                            value: value,
                            backgroundColor: fg.withValues(alpha: 0.25),
                            color: fg,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isCurrent && pos > Duration.zero
                                ? _fmt(pos)
                                : _fmt(dur),
                            style: TextStyle(color: fg, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
