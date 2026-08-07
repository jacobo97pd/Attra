import 'dart:typed_data';

// `camera` reexporta XFile (ambos salen de cross_file), asi que no se importa
// image_picker aqui: seria el mismo tipo por dos caminos.
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../domain/story.dart';

/// Acceso a cámara y carrete detrás de interfaces.
///
/// No es ceremonia: `camera` y `photo_manager` hablan por canales nativos, así
/// que sin esta separación la pantalla del compositor sería intestable y
/// tendríamos la pantalla más nueva de la app sin una sola prueba.

/// Cámara en vivo dentro de la app.
///
/// El selector del sistema (`image_picker`) no vale aquí: abre otra pantalla y
/// no deja pintar el carrete encima, que es justo lo que se pidió.
abstract class StoryCamera {
  /// Vista previa lista para pintar. `null` mientras no esté inicializada.
  Widget? preview();

  bool get isReady;
  bool get isRecording;

  /// ¿Hay más de una cámara para poder girar?
  bool get canFlip;

  Future<void> initialize();

  /// Cambia entre frontal y trasera. No hace nada si solo hay una.
  Future<void> flip();

  Future<XFile?> takePhoto();

  Future<void> startVideo();

  /// Devuelve el vídeo grabado, o `null` si no se estaba grabando.
  Future<XFile?> stopVideo();

  Future<void> dispose();
}

/// Una foto o vídeo del carrete.
class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.type,
    this.videoDuration,
  });

  final String id;
  final StoryMediaType type;
  final Duration? videoDuration;
}

/// El carrete del teléfono.
abstract class StoryGallery {
  /// Pide permiso. `false` si la persona lo deniega.
  Future<bool> ensurePermission();

  /// Página de elementos, del más reciente al más antiguo.
  Future<List<GalleryItem>> load({required int page, int pageSize});

  /// Miniatura para la cuadrícula.
  Future<Uint8List?> thumbnail(String id, {int size});

  /// Fichero real, ya descargado. `null` si no se pudo obtener (asset de iCloud
  /// que no baja, o borrado entre la carga y el toque).
  Future<XFile?> file(String id);
}

// ---------------------------------------------------------------------------
// Implementaciones reales
// ---------------------------------------------------------------------------

class DeviceStoryCamera implements StoryCamera {
  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  int _index = 0;
  bool _recording = false;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  bool get isRecording => _recording;

  @override
  bool get canFlip => _cameras.length > 1;

  @override
  Widget? preview() {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    return CameraPreview(c);
  }

  @override
  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    // Se arranca en la trasera si existe: es la que espera quien abre la cámara
    // para enseñar algo, no para hacerse un selfie.
    final int back = _cameras.indexWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
    );
    _index = back >= 0 ? back : 0;
    await _open();
  }

  Future<void> _open() async {
    final CameraController controller = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      // El audio se habilita desde el principio: pedirlo al empezar a grabar
      // obligaría a reabrir la cámara a mitad de gesto.
      enableAudio: true,
    );
    await controller.initialize();
    await _controller?.dispose();
    _controller = controller;
  }

  @override
  Future<void> flip() async {
    if (!canFlip || _recording) return;
    _index = (_index + 1) % _cameras.length;
    await _open();
  }

  @override
  Future<XFile?> takePhoto() async {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized || _recording) return null;
    return c.takePicture();
  }

  @override
  Future<void> startVideo() async {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized || _recording) return;
    await c.startVideoRecording();
    _recording = true;
  }

  @override
  Future<XFile?> stopVideo() async {
    final CameraController? c = _controller;
    if (c == null || !_recording) return null;
    _recording = false;
    return c.stopVideoRecording();
  }

  @override
  Future<void> dispose() async {
    // Si se sale con la grabación en marcha hay que pararla ANTES de soltar el
    // controlador o el fichero queda a medias y el sistema mantiene la cámara
    // tomada hasta que se mata la app.
    if (_recording) {
      try {
        await _controller?.stopVideoRecording();
      } catch (_) {
        // Da igual: nos vamos igualmente.
      }
      _recording = false;
    }
    await _controller?.dispose();
    _controller = null;
  }
}

class DeviceStoryGallery implements StoryGallery {
  AssetPathEntity? _album;
  final Map<String, AssetEntity> _cache = <String, AssetEntity>{};

  @override
  Future<bool> ensurePermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    // `limited` (iOS: "seleccionar fotos") cuenta como sí: se ve lo que la
    // persona decidió compartir, que es exactamente lo que pidió.
    return state == PermissionState.authorized ||
        state == PermissionState.limited;
  }

  @override
  Future<List<GalleryItem>> load({required int page, int pageSize = 60}) async {
    _album ??= (await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: <OrderOption>[
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    ))
        .firstOrNull;
    final AssetPathEntity? album = _album;
    if (album == null) return const <GalleryItem>[];

    final List<AssetEntity> assets =
        await album.getAssetListPaged(page: page, size: pageSize);
    return assets.map((AssetEntity a) {
      _cache[a.id] = a;
      final bool isVideo = a.type == AssetType.video;
      return GalleryItem(
        id: a.id,
        type: isVideo ? StoryMediaType.video : StoryMediaType.image,
        videoDuration: isVideo ? Duration(seconds: a.duration) : null,
      );
    }).toList(growable: false);
  }

  @override
  Future<Uint8List?> thumbnail(String id, {int size = 240}) async {
    final AssetEntity? asset = _cache[id] ?? await AssetEntity.fromId(id);
    return asset?.thumbnailDataWithSize(ThumbnailSize.square(size));
  }

  @override
  Future<XFile?> file(String id) async {
    final AssetEntity? asset = _cache[id] ?? await AssetEntity.fromId(id);
    if (asset == null) return null;
    // `originFile` puede tardar: en iOS dispara la descarga desde iCloud.
    final file = await asset.originFile ?? await asset.file;
    return file == null ? null : XFile(file.path);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
