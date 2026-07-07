import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../widgets/attra_loader.dart';
import '../data/story_service.dart';
import '../domain/story.dart';

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
  static const Duration _maxVideoDuration = Duration(seconds: 15);
  static const int _photoStorySeconds = 5;
  static const List<Color> _palette = <Color>[
    Colors.white,
    Colors.black,
    Color(0xFFE63946),
    Color(0xFFFFC857),
    Color(0xFF2EC4B6),
    Color(0xFF3A86FF),
    Color(0xFFFF7A59),
  ];
  static const List<String> _stickers = <String>[
    '❤️',
    '🔥',
    '✨',
    '😂',
    '😍',
    '🥰',
    '💋',
    '🎉',
    '⭐',
    '🌙',
    '☕',
    '📍',
  ];

  final ImagePicker _picker = ImagePicker();
  XFile? _media;
  StoryMediaType? _mediaType;
  VideoPlayerController? _preview;
  Uint8List? _imagePreviewBytes;
  StoryVisibility _visibility = StoryVisibility.discovery;
  bool _publishing = false;
  StoryImageFilter _imageFilter = StoryImageFilter.none;
  int _imageRotationTurns = 0;
  double _imageCropZoom = 1.0;
  double _videoSourceDurationSeconds = 15.0;
  double _videoTrimStartSeconds = 0.0;
  double _videoTrimEndSeconds = 15.0;
  double _videoCoverSeconds = 0.0;
  bool _videoMuted = false;

  final List<_EditableStoryOverlay> _overlays = <_EditableStoryOverlay>[];
  int? _selectedOverlayIndex;
  double _gestureStartX = 0.5;
  double _gestureStartY = 0.5;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  Offset _gestureStartFocal = Offset.zero;

  _EditableStoryOverlay? get _selectedOverlay {
    final int? index = _selectedOverlayIndex;
    if (index == null || index < 0 || index >= _overlays.length) return null;
    return _overlays[index];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostMedia());
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pickGallery() async {
    try {
      final XFile? file = await _picker.pickMedia(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      final StoryMediaType? type = _detectMediaType(file);
      if (type == null) {
        _snack('El archivo elegido no es una foto o video compatible.');
        return;
      }
      await _useMedia(file, type);
    } on PlatformException catch (e) {
      _snack(_pickErrorMessage(e, 'seleccionar de la galeria'));
    } catch (_) {
      _snack('No se pudo seleccionar de la galeria.');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      await _useMedia(file, StoryMediaType.image);
    } on PlatformException catch (e) {
      _snack(_pickErrorMessage(e, 'hacer la foto'));
    } catch (_) {
      _snack('No se pudo abrir la camara para hacer la foto.');
    }
  }

  Future<void> _recordVideo() async {
    try {
      final XFile? file = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxDuration: _maxVideoDuration,
      );
      if (file == null || !mounted) return;
      await _useMedia(file, StoryMediaType.video);
    } on PlatformException catch (e) {
      _snack(_pickErrorMessage(e, 'grabar el video'));
    } catch (_) {
      _snack('No se pudo abrir la camara para grabar.');
    }
  }

  Future<void> _recoverLostMedia() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      if (!mounted || response.isEmpty) return;
      final PlatformException? exception = response.exception;
      if (exception != null) {
        _snack(_pickErrorMessage(exception, 'recuperar el contenido'));
        return;
      }
      final List<XFile>? files = response.files;
      final XFile? file = response.file ??
          (files != null && files.isNotEmpty ? files.first : null);
      if (file == null) return;
      final StoryMediaType? type = switch (response.type) {
        RetrieveType.image => StoryMediaType.image,
        RetrieveType.video => StoryMediaType.video,
        RetrieveType.media || null => _detectMediaType(file),
      };
      if (type == null) return;
      await _useMedia(file, type);
    } on UnimplementedError {
      return;
    } catch (_) {
      if (mounted) _snack('No se pudo recuperar el contenido capturado.');
    }
  }

  Future<void> _useMedia(XFile file, StoryMediaType type) async {
    _preview?.dispose();

    if (type == StoryMediaType.image) {
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _media = file;
        _mediaType = type;
        _imagePreviewBytes = bytes;
        _preview = null;
        _imageFilter = StoryImageFilter.none;
        _imageRotationTurns = 0;
        _imageCropZoom = 1.0;
        _videoSourceDurationSeconds = 15.0;
        _videoTrimStartSeconds = 0.0;
        _videoTrimEndSeconds = 15.0;
        _videoCoverSeconds = 0.0;
        _videoMuted = false;
        _selectedOverlayIndex = null;
      });
      return;
    }

    final VideoPlayerController controller = _createPreviewController(file);
    bool initialized = false;
    int durationSeconds = 10;
    double sourceDurationSeconds = 10.0;
    try {
      await controller.initialize();
      initialized = controller.value.isInitialized;
      if (initialized) {
        final int actualSeconds = controller.value.duration.inSeconds;
        durationSeconds =
            actualSeconds.clamp(1, _maxVideoDuration.inSeconds).toInt();
        sourceDurationSeconds = actualSeconds <= 0
            ? durationSeconds.toDouble()
            : actualSeconds.toDouble();
      }
    } catch (_) {
      // Aunque la preview falle, el archivo puede publicarse.
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _media = file;
      _mediaType = type;
      _imagePreviewBytes = null;
      _preview = initialized ? controller : null;
      _imageFilter = StoryImageFilter.none;
      _imageRotationTurns = 0;
      _imageCropZoom = 1.0;
      _videoSourceDurationSeconds = sourceDurationSeconds
          .clamp(
            1.0,
            3600.0,
          )
          .toDouble();
      _videoTrimStartSeconds = 0.0;
      _videoTrimEndSeconds = sourceDurationSeconds
          .clamp(
            1.0,
            _maxVideoDuration.inSeconds.toDouble(),
          )
          .toDouble();
      _videoCoverSeconds = 0.0;
      _videoMuted = false;
      _selectedOverlayIndex = null;
    });
    if (_preview != null) {
      _preview!
        ..setLooping(true)
        ..play();
    } else {
      controller.dispose();
    }
  }

  VideoPlayerController _createPreviewController(XFile file) {
    final Uri uri = kIsWeb ? Uri.parse(file.path) : Uri.file(file.path);
    return VideoPlayerController.networkUrl(uri);
  }

  StoryMediaType? _detectMediaType(XFile file) {
    final String mime = file.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) return StoryMediaType.image;
    if (mime.startsWith('video/')) return StoryMediaType.video;

    final String source = '${file.name} ${file.path}'.toLowerCase();
    const List<String> imageExt = <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.heif',
      '.webp',
    ];
    const List<String> videoExt = <String>[
      '.mp4',
      '.mov',
      '.m4v',
      '.webm',
      '.3gp',
    ];
    if (imageExt.any(source.contains)) return StoryMediaType.image;
    if (videoExt.any(source.contains)) return StoryMediaType.video;
    return null;
  }

  String _pickErrorMessage(PlatformException e, String action) {
    switch (e.code) {
      case 'camera_access_denied':
      case 'camera_access_restricted':
        return 'Attra no tiene permiso para usar la camara. Revisalo en ajustes del dispositivo.';
      case 'photo_access_denied':
      case 'photo_access_restricted':
        return 'Attra no tiene permiso para acceder a tus fotos. Revisalo en ajustes del dispositivo.';
      case 'no_available_camera':
        return 'No hay ninguna camara disponible en este dispositivo.';
      case 'already_active':
        return 'Ya hay una seleccion de media abierta.';
    }
    final String detail = e.message?.trim() ?? '';
    return detail.isEmpty
        ? 'No se pudo $action.'
        : 'No se pudo $action: $detail';
  }

  Future<void> _addTextOverlay() async {
    final String? text = await _askText();
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _overlays.add(
        _EditableStoryOverlay(
          type: StoryOverlayType.text,
          text: text.trim(),
          x: 0.5,
          y: 0.45,
          colorValue: 0xFFFFFFFF,
          background: false,
        ),
      );
      _selectedOverlayIndex = _overlays.length - 1;
    });
  }

  Future<void> _editSelectedText() async {
    final _EditableStoryOverlay? overlay = _selectedOverlay;
    if (overlay == null || overlay.type != StoryOverlayType.text) return;
    final String? text = await _askText(initial: overlay.text);
    if (text == null || text.trim().isEmpty) return;
    setState(() => overlay.text = text.trim());
  }

  Future<String?> _askText({String initial = ''}) async {
    final TextEditingController controller =
        TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Texto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Escribe algo'),
          textInputAction: TextInputAction.done,
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addStickerOverlay() async {
    final String? sticker = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 6,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            children: <Widget>[
              for (final String sticker in _stickers)
                InkWell(
                  onTap: () => Navigator.of(context).pop(sticker),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(sticker, style: const TextStyle(fontSize: 32)),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (sticker == null) return;
    setState(() {
      _overlays.add(
        _EditableStoryOverlay(
          type: StoryOverlayType.sticker,
          text: sticker,
          x: 0.5,
          y: 0.45,
          scale: 1.2,
          colorValue: 0xFFFFFFFF,
        ),
      );
      _selectedOverlayIndex = _overlays.length - 1;
    });
  }

  void _removeSelectedOverlay() {
    final int? index = _selectedOverlayIndex;
    if (index == null || index < 0 || index >= _overlays.length) return;
    setState(() {
      _overlays.removeAt(index);
      _selectedOverlayIndex = _overlays.isEmpty
          ? null
          : index.clamp(0, _overlays.length - 1).toInt();
    });
  }

  void _selectOverlayColor(Color color) {
    final _EditableStoryOverlay? overlay = _selectedOverlay;
    if (overlay == null || overlay.type != StoryOverlayType.text) return;
    setState(() => overlay.colorValue = color.toARGB32());
  }

  void _toggleOverlayBackground() {
    final _EditableStoryOverlay? overlay = _selectedOverlay;
    if (overlay == null || overlay.type != StoryOverlayType.text) return;
    setState(() => overlay.background = !overlay.background);
  }

  void _cycleOverlayAlign() {
    final _EditableStoryOverlay? overlay = _selectedOverlay;
    if (overlay == null || overlay.type != StoryOverlayType.text) return;
    setState(() {
      overlay.align = switch (overlay.align) {
        StoryOverlayAlign.center => StoryOverlayAlign.left,
        StoryOverlayAlign.left => StoryOverlayAlign.right,
        StoryOverlayAlign.right => StoryOverlayAlign.center,
      };
    });
  }

  void _setOverlayScale(double value) {
    final _EditableStoryOverlay? overlay = _selectedOverlay;
    if (overlay == null) return;
    setState(() => overlay.scale = value);
  }

  void _onOverlayScaleStart(int index, ScaleStartDetails details) {
    final _EditableStoryOverlay overlay = _overlays[index];
    _gestureStartX = overlay.x;
    _gestureStartY = overlay.y;
    _gestureStartScale = overlay.scale;
    _gestureStartRotation = overlay.rotation;
    _gestureStartFocal = details.focalPoint;
    setState(() => _selectedOverlayIndex = index);
  }

  void _onOverlayScaleUpdate(
    int index,
    ScaleUpdateDetails details,
    Size canvasSize,
  ) {
    final _EditableStoryOverlay overlay = _overlays[index];
    final Offset delta = details.focalPoint - _gestureStartFocal;
    setState(() {
      overlay.x = (_gestureStartX + delta.dx / canvasSize.width).clamp(0, 1);
      overlay.y = (_gestureStartY + delta.dy / canvasSize.height).clamp(0, 1);
      overlay.scale = (_gestureStartScale * details.scale).clamp(0.4, 3.0);
      overlay.rotation =
          (_gestureStartRotation + details.rotation).clamp(-6.2832, 6.2832);
    });
  }

  List<StoryOverlay> _storyOverlays() {
    return _overlays
        .where(
            (_EditableStoryOverlay overlay) => overlay.text.trim().isNotEmpty)
        .map((_EditableStoryOverlay overlay) => overlay.toStoryOverlay())
        .toList(growable: false);
  }

  void _rotateImage(int delta) {
    setState(() => _imageRotationTurns = (_imageRotationTurns + delta) % 4);
  }

  void _setImageFilter(StoryImageFilter filter) {
    setState(() => _imageFilter = filter);
  }

  void _setImageCropZoom(double value) {
    setState(() => _imageCropZoom = value.clamp(1.0, 2.5).toDouble());
  }

  void _setVideoMuted(bool value) {
    setState(() => _videoMuted = value);
    _preview?.setVolume(value ? 0 : 1);
  }

  void _setVideoTrim(RangeValues values) {
    final double maxDuration = _maxVideoDuration.inSeconds.toDouble();
    final double sourceDuration =
        _videoSourceDurationSeconds.clamp(1.0, 3600.0).toDouble();
    double start = values.start.clamp(0.0, sourceDuration - 1.0).toDouble();
    double end = values.end.clamp(start + 1.0, sourceDuration).toDouble();
    if (end - start > maxDuration) {
      final bool movedStart = (values.start - _videoTrimStartSeconds).abs() >
          (values.end - _videoTrimEndSeconds).abs();
      if (movedStart) {
        start = (end - maxDuration).clamp(0.0, sourceDuration - 1.0).toDouble();
      } else {
        end =
            (start + maxDuration).clamp(start + 1.0, sourceDuration).toDouble();
      }
    }
    final double cover = _videoCoverSeconds.clamp(start, end).toDouble();
    setState(() {
      _videoTrimStartSeconds = start;
      _videoTrimEndSeconds = end;
      _videoCoverSeconds = cover;
    });
    _preview?.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  void _setVideoCover(double value) {
    final double cover =
        value.clamp(_videoTrimStartSeconds, _videoTrimEndSeconds).toDouble();
    setState(() => _videoCoverSeconds = cover);
    _preview?.seekTo(Duration(milliseconds: (cover * 1000).round()));
  }

  int _publishDurationSeconds(StoryMediaType mediaType) {
    if (mediaType == StoryMediaType.image) return _photoStorySeconds;
    return (_videoTrimEndSeconds - _videoTrimStartSeconds)
        .round()
        .clamp(1, _maxVideoDuration.inSeconds)
        .toInt();
  }

  StoryImageEdit _currentImageEdit() {
    return StoryImageEdit(
      rotationTurns: _imageRotationTurns,
      cropZoom: _imageCropZoom,
      filter: _imageFilter,
    );
  }

  StoryVideoEdit _currentVideoEdit() {
    return StoryVideoEdit(
      sourceDurationSeconds: _videoSourceDurationSeconds,
      trimStartSeconds: _videoTrimStartSeconds,
      trimEndSeconds: _videoTrimEndSeconds,
      coverPositionSeconds: _videoCoverSeconds,
      muted: _videoMuted,
    );
  }

  Future<void> _publish() async {
    final XFile? media = _media;
    final StoryMediaType? mediaType = _mediaType;
    if (media == null || mediaType == null || _publishing) return;
    final List<StoryOverlay> overlays = _storyOverlays();
    final StoryOverlay? legacyCaption = overlays
        .where((StoryOverlay overlay) => overlay.type == StoryOverlayType.text)
        .cast<StoryOverlay?>()
        .firstWhere((StoryOverlay? overlay) => overlay != null,
            orElse: () => null);

    setState(() => _publishing = true);
    try {
      await runWithAttraLoader(
        context,
        () => widget.storyService.createStory(
          uid: widget.currentUid,
          media: media,
          mediaType: mediaType,
          durationSeconds: _publishDurationSeconds(mediaType),
          caption: legacyCaption?.text ?? '',
          captionX: legacyCaption?.x ?? 0.5,
          captionY: legacyCaption?.y ?? 0.85,
          overlays: overlays,
          imageEdit: _currentImageEdit(),
          videoEdit: _currentVideoEdit(),
          visibility: _visibility,
        ),
        message: 'Publicando tu story...',
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
    final bool hasMedia = _media != null && _mediaType != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva story')),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: !hasMedia
                  ? _Picker(
                      onGallery: _pickGallery,
                      onPhoto: _takePhoto,
                      onVideo: _recordVideo,
                    )
                  : LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final Size canvasSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            _MediaPreview(
                              mediaType: _mediaType,
                              imageBytes: _imagePreviewBytes,
                              controller: _preview,
                              imageFilter: _imageFilter,
                              imageRotationTurns: _imageRotationTurns,
                              imageCropZoom: _imageCropZoom,
                            ),
                            for (int i = 0; i < _overlays.length; i++)
                              _EditableOverlayView(
                                overlay: _overlays[i],
                                selected: i == _selectedOverlayIndex,
                                canvasSize: canvasSize,
                                onScaleStart: (ScaleStartDetails details) =>
                                    _onOverlayScaleStart(i, details),
                                onScaleUpdate: (ScaleUpdateDetails details) =>
                                    _onOverlayScaleUpdate(
                                  i,
                                  details,
                                  canvasSize,
                                ),
                                onTap: () =>
                                    setState(() => _selectedOverlayIndex = i),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            if (hasMedia) ...<Widget>[
              const SizedBox(height: 10),
              _MediaEditToolbar(
                mediaType: _mediaType,
                imageFilter: _imageFilter,
                imageCropZoom: _imageCropZoom,
                onRotateLeft: () => _rotateImage(-1),
                onRotateRight: () => _rotateImage(1),
                onImageFilter: _setImageFilter,
                onImageCropZoom: _setImageCropZoom,
                videoMuted: _videoMuted,
                videoTrim: RangeValues(
                  _videoTrimStartSeconds,
                  _videoTrimEndSeconds,
                ),
                videoDurationSeconds: _videoSourceDurationSeconds,
                videoCoverSeconds: _videoCoverSeconds,
                onVideoMuted: _setVideoMuted,
                onVideoTrim: _setVideoTrim,
                onVideoCover: _setVideoCover,
              ),
              const SizedBox(height: 8),
              _EditorToolbar(
                selectedOverlay: _selectedOverlay,
                palette: _palette,
                onAddText: _addTextOverlay,
                onAddSticker: _addStickerOverlay,
                onEditText: _editSelectedText,
                onDelete: _removeSelectedOverlay,
                onColor: _selectOverlayColor,
                onToggleBackground: _toggleOverlayBackground,
                onCycleAlign: _cycleOverlayAlign,
                onScale: _setOverlayScale,
              ),
              const SizedBox(height: 10),
              SegmentedButton<StoryVisibility>(
                segments: const <ButtonSegment<StoryVisibility>>[
                  ButtonSegment<StoryVisibility>(
                    value: StoryVisibility.discovery,
                    label: Text('Descubrimiento'),
                  ),
                  ButtonSegment<StoryVisibility>(
                    value: StoryVisibility.matches,
                    label: Text('Solo matches'),
                  ),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload),
                label: Text(_publishing ? 'Publicando...' : 'Publicar story'),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _EditableStoryOverlay {
  _EditableStoryOverlay({
    required this.type,
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.colorValue = 0xFFFFFFFF,
    this.background = false,
  });

  final StoryOverlayType type;
  String text;
  double x;
  double y;
  double scale;
  double rotation = 0.0;
  int colorValue;
  bool background;
  StoryOverlayAlign align = StoryOverlayAlign.center;

  StoryOverlay toStoryOverlay() {
    return StoryOverlay(
      type: type,
      text: text,
      x: x,
      y: y,
      scale: scale,
      rotation: rotation,
      colorValue: colorValue,
      background: background,
      align: align,
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.onGallery,
    required this.onPhoto,
    required this.onVideo,
  });

  final VoidCallback onGallery;
  final VoidCallback onPhoto;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.auto_stories_outlined, size: 64),
          const SizedBox(height: 12),
          const Text('Foto o video para tu story'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeria'),
              ),
              FilledButton.icon(
                onPressed: onPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Foto'),
              ),
              FilledButton.icon(
                onPressed: onVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Video'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaEditToolbar extends StatelessWidget {
  const _MediaEditToolbar({
    required this.mediaType,
    required this.imageFilter,
    required this.imageCropZoom,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onImageFilter,
    required this.onImageCropZoom,
    required this.videoMuted,
    required this.videoTrim,
    required this.videoDurationSeconds,
    required this.videoCoverSeconds,
    required this.onVideoMuted,
    required this.onVideoTrim,
    required this.onVideoCover,
  });

  final StoryMediaType? mediaType;
  final StoryImageFilter imageFilter;
  final double imageCropZoom;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final ValueChanged<StoryImageFilter> onImageFilter;
  final ValueChanged<double> onImageCropZoom;
  final bool videoMuted;
  final RangeValues videoTrim;
  final double videoDurationSeconds;
  final double videoCoverSeconds;
  final ValueChanged<bool> onVideoMuted;
  final ValueChanged<RangeValues> onVideoTrim;
  final ValueChanged<double> onVideoCover;

  @override
  Widget build(BuildContext context) {
    if (mediaType == StoryMediaType.image) {
      return _buildImageControls(context);
    }
    if (mediaType == StoryMediaType.video) {
      return _buildVideoControls(context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildImageControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            IconButton.filledTonal(
              tooltip: 'Girar izquierda',
              onPressed: onRotateLeft,
              icon: const Icon(Icons.rotate_left_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Girar derecha',
              onPressed: onRotateRight,
              icon: const Icon(Icons.rotate_right_rounded),
            ),
            DropdownButton<StoryImageFilter>(
              value: imageFilter,
              borderRadius: BorderRadius.circular(8),
              underline: const SizedBox.shrink(),
              onChanged: (StoryImageFilter? value) {
                if (value != null) onImageFilter(value);
              },
              items: <DropdownMenuItem<StoryImageFilter>>[
                for (final StoryImageFilter filter in StoryImageFilter.values)
                  DropdownMenuItem<StoryImageFilter>(
                    value: filter,
                    child: Text(filter.label),
                  ),
              ],
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.crop_free_rounded, size: 18),
            Expanded(
              child: Slider(
                min: 1.0,
                max: 2.5,
                divisions: 15,
                value: imageCropZoom.clamp(1.0, 2.5).toDouble(),
                onChanged: onImageCropZoom,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVideoControls(BuildContext context) {
    final double duration = videoDurationSeconds.clamp(1.0, 3600.0).toDouble();
    final double start = videoTrim.start.clamp(0.0, duration - 1.0).toDouble();
    final double end = videoTrim.end.clamp(start + 1.0, duration).toDouble();
    final double cover = videoCoverSeconds.clamp(start, end).toDouble();
    final int rangeDivisions = duration.round().clamp(1, 3600).toInt();
    final int coverDivisions = (end - start).round().clamp(1, 15).toInt();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton.filledTonal(
              tooltip: videoMuted ? 'Activar audio' : 'Mutear',
              onPressed: () => onVideoMuted(!videoMuted),
              icon: Icon(
                videoMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Text('${start.round()}s - ${end.round()}s'),
            Expanded(
              child: RangeSlider(
                min: 0,
                max: duration,
                divisions: rangeDivisions,
                values: RangeValues(start, end),
                labels: RangeLabels(
                  '${start.round()}s',
                  '${end.round()}s',
                ),
                onChanged: onVideoTrim,
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.image_outlined, size: 18),
            Expanded(
              child: Slider(
                min: start,
                max: end,
                divisions: coverDivisions,
                value: cover,
                label: '${cover.round()}s',
                onChanged: onVideoCover,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.selectedOverlay,
    required this.palette,
    required this.onAddText,
    required this.onAddSticker,
    required this.onEditText,
    required this.onDelete,
    required this.onColor,
    required this.onToggleBackground,
    required this.onCycleAlign,
    required this.onScale,
  });

  final _EditableStoryOverlay? selectedOverlay;
  final List<Color> palette;
  final VoidCallback onAddText;
  final VoidCallback onAddSticker;
  final VoidCallback onEditText;
  final VoidCallback onDelete;
  final ValueChanged<Color> onColor;
  final VoidCallback onToggleBackground;
  final VoidCallback onCycleAlign;
  final ValueChanged<double> onScale;

  @override
  Widget build(BuildContext context) {
    final _EditableStoryOverlay? selected = selectedOverlay;
    final bool textSelected = selected?.type == StoryOverlayType.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            IconButton.filledTonal(
              tooltip: 'Texto',
              onPressed: onAddText,
              icon: const Icon(Icons.title_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Sticker',
              onPressed: onAddSticker,
              icon: const Icon(Icons.add_reaction_outlined),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: textSelected ? onEditText : null,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Fondo',
              onPressed: textSelected ? onToggleBackground : null,
              icon: Icon(
                selected?.background == true
                    ? Icons.format_color_fill_rounded
                    : Icons.format_color_fill_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Alineacion',
              onPressed: textSelected ? onCycleAlign : null,
              icon: const Icon(Icons.format_align_center_rounded),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: selected == null ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        if (textSelected) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final Color color in palette)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => onColor(color),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(
                          width:
                              selected?.colorValue == color.toARGB32() ? 3 : 1,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (selected != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.format_size_rounded, size: 18),
              Expanded(
                child: Slider(
                  min: 0.4,
                  max: 3.0,
                  value: selected.scale.clamp(0.4, 3.0),
                  onChanged: onScale,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EditableOverlayView extends StatelessWidget {
  const _EditableOverlayView({
    required this.overlay,
    required this.selected,
    required this.canvasSize,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onTap,
  });

  final _EditableStoryOverlay overlay;
  final bool selected;
  final Size canvasSize;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double width = overlay.type == StoryOverlayType.sticker ? 120 : 240;
    final double height = overlay.type == StoryOverlayType.sticker ? 90 : 92;
    return Positioned(
      left: overlay.x * canvasSize.width - width / 2,
      top: overlay.y * canvasSize.height - height / 2,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        child: Transform.rotate(
          angle: overlay.rotation,
          child: Transform.scale(
            scale: overlay.scale,
            child: _OverlayContent(overlay: overlay, selected: selected),
          ),
        ),
      ),
    );
  }
}

class _OverlayContent extends StatelessWidget {
  const _OverlayContent({required this.overlay, required this.selected});

  final _EditableStoryOverlay overlay;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(8);
    final BoxDecoration decoration = BoxDecoration(
      color: overlay.background && overlay.type == StoryOverlayType.text
          ? Colors.black.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: radius,
      border: selected
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
          : null,
    );

    if (overlay.type == StoryOverlayType.sticker) {
      return Container(
        alignment: Alignment.center,
        decoration: decoration,
        child: Text(overlay.text, style: const TextStyle(fontSize: 48)),
      );
    }

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: decoration,
      child: Text(
        overlay.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: _textAlign(overlay.align),
        style: TextStyle(
          color: Color(overlay.colorValue),
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.08,
          shadows: const <Shadow>[
            Shadow(blurRadius: 8, color: Colors.black87),
            Shadow(blurRadius: 2, color: Colors.black),
          ],
        ),
      ),
    );
  }

  TextAlign _textAlign(StoryOverlayAlign align) {
    return switch (align) {
      StoryOverlayAlign.left => TextAlign.left,
      StoryOverlayAlign.center => TextAlign.center,
      StoryOverlayAlign.right => TextAlign.right,
    };
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.mediaType,
    required this.imageBytes,
    required this.controller,
    required this.imageFilter,
    required this.imageRotationTurns,
    required this.imageCropZoom,
  });

  final StoryMediaType? mediaType;
  final Uint8List? imageBytes;
  final VideoPlayerController? controller;
  final StoryImageFilter imageFilter;
  final int imageRotationTurns;
  final double imageCropZoom;

  @override
  Widget build(BuildContext context) {
    if (mediaType == StoryMediaType.image && imageBytes != null) {
      Widget image = Image.memory(imageBytes!, fit: BoxFit.cover);
      image = Transform.scale(
        scale: imageCropZoom.clamp(1.0, 2.5).toDouble(),
        child: image,
      );
      image = RotatedBox(
        quarterTurns: imageRotationTurns % 4,
        child: image,
      );
      final ColorFilter? filter = _previewFilter(imageFilter);
      if (filter != null) {
        image = ColorFiltered(colorFilter: filter, child: image);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black,
          child: SizedBox.expand(child: image),
        ),
      );
    }

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
              Text('Contenido listo para publicar'),
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

  ColorFilter? _previewFilter(StoryImageFilter filter) {
    return switch (filter) {
      StoryImageFilter.none => null,
      StoryImageFilter.warm => const ColorFilter.matrix(<double>[
          1.08,
          0,
          0,
          0,
          8,
          0,
          1.02,
          0,
          0,
          2,
          0,
          0,
          0.94,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
      StoryImageFilter.cool => const ColorFilter.matrix(<double>[
          0.94,
          0,
          0,
          0,
          0,
          0,
          1.02,
          0,
          0,
          0,
          0,
          0,
          1.1,
          0,
          4,
          0,
          0,
          0,
          1,
          0,
        ]),
      StoryImageFilter.mono => const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
      StoryImageFilter.punch => const ColorFilter.matrix(<double>[
          1.16,
          -0.04,
          -0.04,
          0,
          0,
          -0.04,
          1.16,
          -0.04,
          0,
          0,
          -0.04,
          -0.04,
          1.16,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    };
  }
}
