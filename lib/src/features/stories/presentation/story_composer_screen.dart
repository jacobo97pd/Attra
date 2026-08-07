import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../widgets/attra_loader.dart';
import '../data/story_media_sources.dart';
import '../data/story_service.dart';
import '../domain/story.dart';
import '../domain/story_composer.dart';

/// Compositor de historias: la cámara SE ABRE al entrar y el carrete sube
/// deslizando hacia arriba, sin cambiar de pantalla.
///
/// Sustituye al editor anterior (texto, pegatinas, recorte de vídeo, portada,
/// silenciar), que obligaba a pasar por un taller antes de publicar algo. Aquí
/// se elige y se publica. El vídeo NO se ha perdido: pulsar dispara foto,
/// mantener graba.
class StoryComposerScreen extends StatefulWidget {
  const StoryComposerScreen({
    super.key,
    required this.currentUid,
    required this.storyService,
    this.camera,
    this.gallery,
  });

  final String currentUid;
  final StoryService storyService;

  /// Inyectables para poder montar la pantalla en tests: las de verdad hablan
  /// por canal nativo y no existen en el entorno de pruebas.
  final StoryCamera? camera;
  final StoryGallery? gallery;

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  late final StoryCamera _camera = widget.camera ?? DeviceStoryCamera();
  late final StoryGallery _gallery = widget.gallery ?? DeviceStoryGallery();

  StoryComposerMode _mode = StoryComposerMode.camera;
  bool _cameraFailed = false;
  bool _publishing = false;

  final List<GalleryItem> _items = <GalleryItem>[];
  final Map<String, Uint8List?> _thumbs = <String, Uint8List?>{};
  bool _galleryDenied = false;
  bool _galleryLoading = false;
  bool _galleryExhausted = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    try {
      await _camera.initialize();
    } catch (_) {
      // Sin cámara (emulador, permiso denegado, hardware ocupado por otra app)
      // NO se muere la pantalla: se abre directamente el carrete, que es la
      // otra mitad de lo que se venía a hacer.
      if (mounted) {
        setState(() {
          _cameraFailed = true;
          _mode = StoryComposerMode.gallery;
        });
        await _openGallery();
        return;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _openGallery() async {
    if (_galleryDenied || _galleryLoading || _galleryExhausted) return;
    setState(() => _galleryLoading = true);
    final bool ok = await _gallery.ensurePermission();
    if (!ok) {
      if (mounted) {
        setState(() {
          _galleryDenied = true;
          _galleryLoading = false;
        });
      }
      return;
    }
    final List<GalleryItem> page =
        await _gallery.load(page: _page, pageSize: 60);
    if (!mounted) return;
    setState(() {
      _items.addAll(page);
      _page++;
      _galleryExhausted = page.isEmpty;
      _galleryLoading = false;
    });
    for (final GalleryItem item in page) {
      _gallery.thumbnail(item.id).then((Uint8List? bytes) {
        if (mounted) setState(() => _thumbs[item.id] = bytes);
      });
    }
  }

  void _showMode(StoryComposerMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == StoryComposerMode.gallery) _openGallery();
  }

  // --- Publicar -------------------------------------------------------------

  Future<void> _publish(StoryDraft draft) async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      await widget.storyService.createStory(
        uid: widget.currentUid,
        media: draft.file,
        mediaType: draft.type,
        durationSeconds: draft.durationSeconds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _say('No hemos podido publicar tu historia. $error');
    }
  }

  Future<void> _choose({
    required XFile? file,
    required StoryMediaType type,
    Duration? videoDuration,
  }) async {
    if (file == null) {
      _say(storyRejectionMessage(StoryMediaRejection.unavailable));
      return;
    }
    final StoryMediaRejection? rejection = checkStoryMedia(
      type: type,
      videoDuration: videoDuration,
    );
    if (rejection != null) {
      _say(storyRejectionMessage(rejection));
      return;
    }
    await _publish(
      StoryDraft(file: file, type: type, videoDuration: videoDuration),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Gestos del disparador ------------------------------------------------

  Future<void> _onShutterTap() async {
    if (_publishing || _camera.isRecording) return;
    await _choose(file: await _camera.takePhoto(), type: StoryMediaType.image);
  }

  Future<void> _onShutterHold() async {
    if (_publishing || !_camera.isReady) return;
    await _camera.startVideo();
    if (mounted) setState(() {});
  }

  Future<void> _onShutterRelease() async {
    if (!_camera.isRecording) return;
    final XFile? file = await _camera.stopVideo();
    if (mounted) setState(() {});
    if (file == null) return;
    // La duración real la pone el fichero; aquí no se conoce sin abrirlo, y el
    // tope ya lo impone el propio gesto (no se puede grabar más de lo que se
    // mantiene pulsado, y el temporizador lo corta).
    await _choose(file: file, type: StoryMediaType.video);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _cameraLayer()),
          if (_mode == StoryComposerMode.gallery)
            Positioned.fill(child: _galleryLayer()),
          if (_publishing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: AttraLogoLoader()),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: const Key('story-composer-close'),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (_mode == StoryComposerMode.camera && _camera.canFlip)
                    IconButton(
                      key: const Key('story-composer-flip'),
                      icon: const Icon(Icons.cameraswitch_rounded,
                          color: Colors.white),
                      onPressed: () async {
                        await _camera.flip();
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraLayer() {
    final Widget? preview = _camera.preview();
    return GestureDetector(
      // Deslizar hacia ARRIBA abre el carrete: es el gesto que se pidió y el
      // que la gente ya trae aprendido de Instagram.
      onVerticalDragEnd: (DragEndDetails d) {
        if (d.primaryVelocity != null && d.primaryVelocity! < -200) {
          _showMode(StoryComposerMode.gallery);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (preview != null)
            preview
          else
            Center(
              child: Text(
                _cameraFailed
                    ? 'No hemos podido abrir la cámara.\nElige una foto de tu '
                        'galería.'
                    : '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          if (_mode == StoryComposerMode.camera)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ShutterButton(
                      recording: _camera.isRecording,
                      enabled: _camera.isReady && !_publishing,
                      onTap: _onShutterTap,
                      onHoldStart: _onShutterHold,
                      onHoldEnd: _onShutterRelease,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('story-composer-open-gallery'),
                      onPressed: () => _showMode(StoryComposerMode.gallery),
                      child: const Text(
                        'Desliza hacia arriba para tu galería',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _galleryLayer() {
    return GestureDetector(
      onVerticalDragEnd: (DragEndDetails d) {
        // Hacia abajo se vuelve a la cámara, salvo que no haya cámara que
        // mostrar: entonces bajar dejaría la pantalla en blanco.
        if (!_cameraFailed &&
            d.primaryVelocity != null &&
            d.primaryVelocity! > 200) {
          _showMode(StoryComposerMode.camera);
        }
      },
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.94),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 44),
              if (_galleryDenied)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Necesitamos permiso para ver tus fotos. Actívalo en '
                        'los ajustes del teléfono.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                )
              else if (_items.isEmpty && _galleryLoading)
                const Expanded(child: Center(child: AttraLogoLoader()))
              else if (_items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No hay fotos en tu galería.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    key: const Key('story-composer-grid'),
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (BuildContext context, int i) {
                      // Al llegar al final se pide la siguiente página: cargar
                      // el carrete entero de golpe agota la memoria en móviles
                      // con miles de fotos.
                      if (i == _items.length - 1) _openGallery();
                      return _GalleryTile(
                        item: _items[i],
                        thumbnail: _thumbs[_items[i].id],
                        onTap: () => _pickFromGallery(_items[i]),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery(GalleryItem item) async {
    // Se valida ANTES de descargar el fichero: si el vídeo es demasiado largo,
    // bajarlo de iCloud para luego rechazarlo sería hacerle esperar para nada.
    final StoryMediaRejection? rejection = checkStoryMedia(
      type: item.type,
      videoDuration: item.videoDuration,
    );
    if (rejection != null) {
      _say(storyRejectionMessage(rejection));
      return;
    }
    setState(() => _publishing = true);
    final XFile? file = await _gallery.file(item.id);
    if (!mounted) return;
    setState(() => _publishing = false);
    await _choose(
      file: file,
      type: item.type,
      videoDuration: item.videoDuration,
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.recording,
    required this.enabled,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool recording;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('story-composer-shutter'),
      onTap: enabled ? onTap : null,
      onLongPressStart: enabled ? (_) => onHoldStart() : null,
      onLongPressEnd: enabled ? (_) => onHoldEnd() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: recording ? 86 : 74,
        height: recording ? 86 : 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? Colors.redAccent : Colors.white24,
          border: Border.all(
            color: enabled ? Colors.white : Colors.white38,
            width: 4,
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.item,
    required this.thumbnail,
    required this.onTap,
  });

  final GalleryItem item;
  final Uint8List? thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = thumbnail;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (bytes != null)
            Image.memory(bytes, fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.white10),
          if (item.type == StoryMediaType.video)
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.videocam_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
