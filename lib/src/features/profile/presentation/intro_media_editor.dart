import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../domain/intro_media.dart';
import 'intro_media_view.dart';

/// Parámetros de subida que el editor entrega al exterior.
typedef IntroUpload = Future<void> Function({
  required Uint8List bytes,
  required String contentType,
  required String extension,
  required int durationMs,
});

/// Editor de la media de presentación del perfil: grabar un AUDIO ("voice
/// prompt") y subir un VÍDEO corto. Autónomo: carga su estado, graba/sube/borra
/// y se refresca. La persistencia la hacen los callbacks (repositorio).
class IntroMediaEditor extends StatefulWidget {
  const IntroMediaEditor({
    super.key,
    required this.loadMedia,
    required this.onUploadAudio,
    required this.onDeleteAudio,
    required this.onUploadVideo,
    required this.onDeleteVideo,
  });

  final Future<({IntroAudio? audio, IntroVideo? video})> Function() loadMedia;
  final IntroUpload onUploadAudio;
  final Future<void> Function() onDeleteAudio;
  final IntroUpload onUploadVideo;
  final Future<void> Function() onDeleteVideo;

  /// Límites.
  static const int maxAudioSeconds = 60;
  static const int maxVideoSeconds = 30;

  @override
  State<IntroMediaEditor> createState() => _IntroMediaEditorState();
}

class _IntroMediaEditorState extends State<IntroMediaEditor> {
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  IntroAudio? _audio;
  IntroVideo? _video;
  bool _loading = true;
  bool _busy = false; // subiendo/borrando

  // Estado de grabación.
  bool _recording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  String _recordContentType = 'audio/m4a';
  String _recordExt = 'm4a';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ({IntroAudio? audio, IntroVideo? video}) m =
          await widget.loadMedia();
      if (!mounted) return;
      setState(() {
        _audio = m.audio;
        _video = m.video;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── AUDIO: grabación ──────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      _snack('Necesito permiso de micrófono para grabar.');
      return;
    }
    // Selecciona un encoder soportado por el dispositivo.
    const List<(AudioEncoder, String, String)> candidates =
        <(AudioEncoder, String, String)>[
      (AudioEncoder.aacLc, 'audio/m4a', 'm4a'),
      (AudioEncoder.opus, 'audio/opus', 'opus'),
      (AudioEncoder.wav, 'audio/wav', 'wav'),
    ];
    AudioEncoder? encoder;
    for (final (AudioEncoder, String, String) c in candidates) {
      if (await _recorder.isEncoderSupported(c.$1)) {
        encoder = c.$1;
        _recordContentType = c.$2;
        _recordExt = c.$3;
        break;
      }
    }
    if (encoder == null) {
      _snack('Tu dispositivo no soporta la grabación de audio.');
      return;
    }
    try {
      final String path =
          kIsWeb ? '' : '${DateTime.now().millisecondsSinceEpoch}.$_recordExt';
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
    } catch (_) {
      _snack('No se pudo iniciar la grabación.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordElapsed = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      setState(() => _recordElapsed += const Duration(seconds: 1));
      if (_recordElapsed.inSeconds >= IntroMediaEditor.maxAudioSeconds) {
        _stopAndUploadAudio();
      }
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndUploadAudio() async {
    _recordTimer?.cancel();
    final int durationMs = _recordElapsed.inMilliseconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null || path.isEmpty || durationMs < 1000) {
      if (durationMs < 1000) _snack('Audio demasiado corto.');
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List bytes = await XFile(path).readAsBytes();
      await widget.onUploadAudio(
        bytes: bytes,
        contentType: _recordContentType,
        extension: _recordExt,
        durationMs: durationMs,
      );
      await _load();
    } catch (e) {
      _snack('No se pudo guardar el audio.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAudio() async {
    setState(() => _busy = true);
    try {
      await widget.onDeleteAudio();
      await _load();
    } catch (_) {
      _snack('No se pudo eliminar el audio.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── VÍDEO: elegir + comprimir + subir ─────────────────────────────────────

  Future<void> _pickAndUploadVideo() async {
    final XFile? file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: IntroMediaEditor.maxVideoSeconds),
    );
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      Uint8List bytes;
      String contentType = file.mimeType ?? 'video/mp4';
      int durationMs = 0;

      if (kIsWeb) {
        bytes = await file.readAsBytes();
      } else {
        try {
          final MediaInfo? info = await VideoCompress.compressVideo(
            file.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          bytes = await XFile(info?.path ?? file.path).readAsBytes();
          contentType = 'video/mp4';
          durationMs = (info?.duration ?? 0).round();
        } catch (_) {
          bytes = await file.readAsBytes();
        }
      }
      await widget.onUploadVideo(
        bytes: bytes,
        contentType: contentType,
        extension: 'mp4',
        durationMs: durationMs,
      );
      await _load();
    } catch (e) {
      _snack('No se pudo subir el vídeo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteVideo() async {
    setState(() => _busy = true);
    try {
      await widget.onDeleteVideo();
      await _load();
    } catch (_) {
      _snack('No se pudo eliminar el vídeo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_motion_rounded,
                  size: 18, color: AppColors.attraRed),
              const SizedBox(width: 8),
              Text('Audio y vídeo de presentación',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Públicos: cualquiera que vea tu perfil podrá reproducirlos.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.colors.textSecondary)),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: AppColors.attraRed),
              ),
            )
          else ...<Widget>[
            _buildAudioSection(theme),
            const SizedBox(height: 16),
            _buildVideoSection(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioSection(ThemeData theme) {
    if (_recording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.attraRed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.fiber_manual_record, color: AppColors.attraRed),
            const SizedBox(width: 10),
            Text('Grabando  ${_fmt(_recordElapsed)}',
                style: TextStyle(
                    color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              tooltip: 'Cancelar',
              onPressed: _cancelRecording,
              icon: Icon(Icons.close_rounded,
                  color: context.colors.textSecondary),
            ),
            IconButton(
              tooltip: 'Listo',
              onPressed: _stopAndUploadAudio,
              icon: const Icon(Icons.check_circle_rounded,
                  color: AppColors.attraRed, size: 30),
            ),
          ],
        ),
      );
    }

    final IntroAudio? audio = _audio;
    if (audio != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IntroAudioPlayer(audio: audio, label: 'Audio de presentación'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _deleteAudio,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Eliminar audio'),
              style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            ),
          ),
        ],
      );
    }

    return _AddTile(
      icon: Icons.mic_rounded,
      title: 'Grabar audio de presentación',
      subtitle: 'Hasta ${IntroMediaEditor.maxAudioSeconds}s',
      onTap: _busy ? null : _startRecording,
    );
  }

  Widget _buildVideoSection(ThemeData theme) {
    final IntroVideo? video = _video;
    if (video != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IntroVideoPlayer(video: video),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _deleteVideo,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Eliminar vídeo'),
              style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            ),
          ),
        ],
      );
    }

    return _AddTile(
      icon: Icons.videocam_rounded,
      title: 'Subir vídeo de presentación',
      subtitle: 'Desde tu galería · hasta ${IntroMediaEditor.maxVideoSeconds}s',
      onTap: _busy ? null : _pickAndUploadVideo,
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: AppColors.attraRed),
            )
          : null,
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: context.colors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.attraRed.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: AppColors.attraRed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.colors.textMuted)),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.add_circle_outline_rounded,
                      color: context.colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
