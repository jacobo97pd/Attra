import 'dart:io';

// `camera` reexporta XFile (ambos salen de cross_file), asi que no se importa
// image_picker aqui: seria el mismo tipo por dos caminos.
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../domain/story.dart';
import '../domain/selfie_mirror.dart';
import '../domain/story_composer.dart';
import '../domain/story_errors.dart';
import 'story_image_conversion.dart';

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

  /// Fichero real, ya descargado y EN UN FORMATO QUE LA APP PUEDE PROCESAR.
  /// `null` si no se pudo obtener (asset de iCloud que no baja, o borrado entre
  /// la carga y el toque).
  ///
  /// Lo del formato es parte del contrato a propósito: quien conoce los formatos
  /// del sistema es el origen del medio, no el servicio que sube ni la pantalla
  /// que publica. Lanza [StoryImageConversionException] si el fichero existe
  /// pero no hay manera de dejarlo procesable.
  Future<XFile?> file(String id);
}

/// Lo que se saca de tocar una foto del carrete: o un fichero listo, o el motivo
/// por el que no, YA redactado para la persona.
///
/// Existe para que la pantalla no tenga que encadenar validación, descarga,
/// conversión y tres formas distintas de fallar: eso es lógica, y la lógica
/// dentro de un `State` no se puede probar.
class StoryPickResult {
  const StoryPickResult.ready(XFile this.file) : message = null;
  const StoryPickResult.rejected(String this.message) : file = null;

  final XFile? file;
  final String? message;

  bool get isReady => file != null;
}

/// Coge del carrete lo que se ha tocado y lo deja listo para publicar.
Future<StoryPickResult> pickStoryMedia(
  StoryGallery gallery,
  GalleryItem item,
) async {
  // Se valida ANTES de pedir el fichero: si el vídeo es demasiado largo, bajarlo
  // de iCloud para luego rechazarlo sería hacerle esperar para nada.
  final StoryMediaRejection? rejection = checkStoryMedia(
    type: item.type,
    videoDuration: item.videoDuration,
  );
  if (rejection != null) {
    return StoryPickResult.rejected(storyRejectionMessage(rejection));
  }

  final XFile? file;
  try {
    file = await gallery.file(item.id);
  } catch (error) {
    // Convertir puede fallar (un HEIC que ni el sistema lee). Sin este catch la
    // excepción salía por la zona de errores de Flutter: la persona se quedaba
    // con la rueda girando y sin saber qué había pasado.
    return StoryPickResult.rejected(storyMediaFailureMessage(error));
  }
  if (file == null) {
    return StoryPickResult.rejected(
      storyRejectionMessage(StoryMediaRejection.unavailable),
    );
  }
  return StoryPickResult.ready(file);
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
    final Size? sensor = c.value.previewSize;
    if (sensor == null) return CameraPreview(c);

    // La vista previa iba SUELTA dentro de un `Stack(fit: StackFit.expand)`, así
    // que se estiraba hasta llenar la pantalla ignorando la proporción del
    // sensor: las caras salían alargadas, en las dos cámaras.
    //
    // `BoxFit.cover` escala MANTENIENDO la proporción y recorta lo que sobra,
    // que es lo que hace la cámara de Instagram: se ve un trozo menor de escena
    // pero sin deformar a nadie.
    //
    // `previewSize` viene en coordenadas del SENSOR, que siempre es apaisado.
    // En vertical hay que intercambiar los lados o la proporción sale invertida
    // y el estiramiento empeora en vez de arreglarse.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: sensor.height,
          height: sensor.width,
          child: CameraPreview(c),
        ),
      ),
    );
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
    // El anterior se SUELTA ANTES de abrir el nuevo. Al girar la cámara se
    // inicializaba el nuevo controlador con el viejo todavía vivo, y en iOS el
    // dispositivo de captura no se comparte: la sesión nueva se creaba pero no
    // entregaba fotogramas, así que la cámara frontal se quedaba EN NEGRO. Que
    // haya un instante sin vista previa es el precio correcto.
    final CameraController? previous = _controller;
    _controller = null;
    await previous?.dispose();

    final CameraController controller = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      // El audio se habilita desde el principio: pedirlo al empezar a grabar
      // obligaría a reabrir la cámara a mitad de gesto.
      enableAudio: true,
    );
    try {
      await controller.initialize();
    } catch (_) {
      // Si esta cámara no abre, se suelta para no dejar el dispositivo tomado
      // por un controlador que nadie va a usar.
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
  }

  @override
  Future<void> flip() async {
    if (!canFlip || _recording) return;
    final int previousIndex = _index;
    _index = (_index + 1) % _cameras.length;
    try {
      await _open();
    } catch (_) {
      // Si la otra cámara falla se vuelve a la que funcionaba, en vez de
      // dejar la pantalla en negro sin vista previa ni forma de recuperarla.
      _index = previousIndex;
      try {
        await _open();
      } catch (_) {
        // Ni una ni otra: la pantalla lo enseñará como cámara no disponible.
      }
    }
  }

  @override
  Future<XFile?> takePhoto() async {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized || _recording) return null;
    final XFile shot = await c.takePicture();

    // El selfie llega EN ESPEJO: en iOS el plugin marca la conexión de la cámara
    // frontal como reflejada (camera_avfoundation, DefaultCamera.swift:158). En
    // la vista previa eso es lo natural, pero en la foto guardada no: el texto
    // sale al revés y la cara no es la que ve el resto del mundo.
    if (!shouldUnmirrorSelfie(
      isFrontLens:
          _cameras[_index].lensDirection == CameraLensDirection.front,
      platformMirrors: _platformMirrorsFrontCamera,
    )) {
      return shot;
    }

    try {
      final Uint8List? fixed =
          unmirrorImageBytes(await shot.readAsBytes());
      if (fixed == null) return shot;
      // Se escribe AL LADO del original en vez de sobrescribirlo: si algo va mal
      // a mitad, el archivo bueno de la cámara sigue intacto.
      final String path =
          '${shot.path}.unmirrored.jpg';
      await File(path).writeAsBytes(fixed, flush: true);
      return XFile(path);
    } catch (error) {
      // Una foto en espejo es infinitamente mejor que ninguna foto: si el
      // volteo falla se publica la original.
      debugPrint('[camara] no se pudo deshacer el espejo: $error');
      return shot;
    }
  }

  /// ¿Refleja esta plataforma la cámara frontal?
  ///
  /// Solo iOS/macOS. En Android, CameraX no refleja la imagen fija, así que
  /// voltearla ahí ROMPERÍA las fotos que hoy salen bien.
  static bool get _platformMirrorsFrontCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

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
  DeviceStoryGallery({StoryImageConverter? converter})
      : _converter = converter ?? StoryImageConverter();

  final StoryImageConverter _converter;
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
    final File? file = await _rawFile(asset);
    if (file == null) return null;
    // El vídeo no pasa por el decodificador de Dart (lo procesa VideoCompress
    // por canal nativo), así que va tal cual.
    if (asset.type == AssetType.video) return XFile(file.path);
    // AQUÍ está el arreglo: `originFile` devuelve el ORIGINAL y en iPhone eso es
    // HEIC, que `img.decodeImage` no sabe leer. Se convierte SOLO si hace falta;
    // un JPEG o un PNG normales salen intactos. El tamaño va también porque una
    // foto legible pero de 24 MP hay que bajarla igual: decodificar eso en Dart
    // congela la pantalla y se come la memoria.
    return XFile(
      await _converter.ensureDecodable(
        file.path,
        sourceWidth: asset.width,
        sourceHeight: asset.height,
      ),
    );
  }

  /// El fichero del carrete, con la caída a la copia comprimida.
  ///
  /// `originFile` no devuelve null cuando falla: `photo_manager` responde con
  /// `replyError` en nativo y en Dart sale una PlatformException, así que el
  /// `?? await asset.file` de antes NUNCA se ejecutaba. Justo el caso que iba a
  /// cubrir (foto en iCloud que no se materializa) es en el que `asset.file` sí
  /// puede tener bytes, porque devuelve la versión ya derivada.
  Future<File?> _rawFile(AssetEntity asset) async {
    try {
      // `originFile` puede tardar: en iOS dispara la descarga desde iCloud.
      final File? origin = await asset.originFile;
      if (origin != null) return origin;
    } catch (_) {
      // Se sigue con la copia derivada: da igual por qué no bajó el original.
    }
    try {
      return await asset.file;
    } catch (_) {
      // Ni original ni derivada: se devuelve null para que quien llama enseñe
      // "puede que se haya borrado o que aún se esté descargando de la nube",
      // que es lo que de verdad ha pasado.
      return null;
    }
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
