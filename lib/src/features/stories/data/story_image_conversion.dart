import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/story_composer.dart';
import '../domain/story_errors.dart';
import '../domain/story_image_format.dart';

/// Garantiza que lo que sale del carrete es algo que la app sabe procesar.
///
/// POR QUÉ vive aquí y no en StoryService: el servicio y el compositor no tienen
/// por qué saber de formatos del sistema operativo. Quien sabe de eso es el
/// origen del medio, así que el carrete es quien tiene que entregar "un fichero
/// que la app puede procesar".

/// Transcodifica una imagen con el decodificador NATIVO del móvil.
///
/// Devuelve la ruta del resultado, o `null` si el sistema tampoco pudo leerla.
/// [maxWidth] y [maxHeight] son la caja en la que tiene que caber el resultado.
/// Está separado en un typedef para poder falsearlo: la implementación real
/// habla por canal nativo y no existe en los tests.
typedef StoryImageTranscoder = Future<String?> Function(
  String sourcePath,
  String targetPath,
  int maxWidth,
  int maxHeight,
);

class StoryImageConversionException implements Exception, StoryUserFacingError {
  const StoryImageConversionException(this.message, {this.cause});

  @override
  final String message;

  /// Error original. Va aparte del [message] para que el volcado del fallo
  /// interno acabe en los logs y no en la cara de la persona.
  final Object? cause;

  @override
  String toString() =>
      cause == null ? message : 'StoryImageConversionException: $message ($cause)';
}

/// Tamaño al que se le pide al transcodificador que deje la imagen.
class StoryTranscodeBox {
  const StoryTranscodeBox(this.width, this.height);

  final int width;
  final int height;

  @override
  String toString() => '${width}x$height';
}

/// Caja que se le pasa al transcodificador nativo.
///
/// POR QUÉ no se pide siempre un cuadrado de [maxSide]: `flutter_image_compress`
/// escala para que la imagen CUBRA la caja, o sea que un cuadrado 1920x1920 deja
/// el lado CORTO en 1920 y el largo por encima (una panorámica 10000x2500 saldría
/// a 7680x1920). Pidiendo una caja con la MISMA proporción que el origen, el lado
/// LARGO acaba en [maxSide] y StoryService ya no tiene que volver a redimensionar
/// en Dart: un solo reescalado, hecho por el resampleador del sistema, en vez de
/// dos (y el segundo por vecino más cercano, que dentaba pelo y tejidos).
///
/// Con el tamaño de origen desconocido (0) se cae a la caja cuadrada, que es el
/// comportamiento de antes: nunca amplía, solo deja el lado largo más grande de
/// lo necesario y entonces sí recorta StoryService.
StoryTranscodeBox storyTranscodeBox({
  required int sourceWidth,
  required int sourceHeight,
  int maxSide = StoryImageConverter.maxSide,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return StoryTranscodeBox(maxSide, maxSide);
  }
  final int longest = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
  if (longest <= maxSide) {
    return StoryTranscodeBox(sourceWidth, sourceHeight);
  }
  final double scale = maxSide / longest;
  final int width = (sourceWidth * scale).round().clamp(1, maxSide).toInt();
  final int height = (sourceHeight * scale).round().clamp(1, maxSide).toInt();
  return StoryTranscodeBox(width, height);
}

class StoryImageConverter {
  StoryImageConverter({
    StoryImageTranscoder? transcode,
    Directory? workDirectory,
  })  : _transcode = transcode ?? _compressToJpeg,
        _workDirectory = workDirectory;

  final StoryImageTranscoder _transcode;
  final Directory? _workDirectory;

  /// Lado LARGO del JPEG convertido.
  ///
  /// 1920 porque es lo que StoryService usa como lado largo máximo: dejándolo ya
  /// en 1920, el redimensionado de Dart se queda en nada y la foto se reescala
  /// una sola vez, con el resampleador del sistema.
  static const int maxSide = 1920;

  /// Presupuesto de píxeles del fichero que se le pasa a `img.decodeImage`.
  ///
  /// POR QUÉ existe: un JPEG de 24 MP (los iPhone recientes con "Más compatible")
  /// no necesita conversión de formato, pero decodificarlo en Dart son ~98 MB de
  /// mapa de bits, otro tanto para `bakeOrientation` y todo en el isolate de la
  /// interfaz. Por encima de este tope se manda al transcodificador nativo
  /// aunque el formato ya fuera legible: baja a 1920 antes de tocar Dart.
  /// 6 MP deja pasar entera la foto de cualquier cámara frontal y las capturas
  /// de pantalla, que son lo que más se publica.
  static const int maxSourcePixels = 6000000;

  /// Subcarpeta propia dentro del temporal de la app.
  ///
  /// Propia y no el temporal a pelo para poder VACIARLA: cada conversión deja un
  /// JPEG de 1-3 MB y nadie los borraba, así que se acumulaban hasta que el
  /// sistema apretaba por falta de espacio.
  static const String workDirectoryName = 'attra_historias';

  /// Cuánto se le deja vivir a un convertido antes de barrerlo.
  ///
  /// No se borra todo a ciegas: el fichero que se acaba de convertir todavía lo
  /// está leyendo StoryService para subirlo.
  static const Duration _keepConverted = Duration(hours: 1);

  /// Ruta de un fichero que la app puede decodificar.
  ///
  /// Devuelve [sourcePath] tal cual si ya era procesable Y no es enorme: un JPEG
  /// o un PNG normales NO se tocan (reencodar pierde calidad sin ganar nada).
  /// [sourceWidth] y [sourceHeight] son los del original, si se conocen: sirven
  /// para decidir el tamaño de salida y para detectar las fotos desmesuradas.
  Future<String> ensureDecodable(
    String sourcePath, {
    int sourceWidth = 0,
    int sourceHeight = 0,
  }) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw StoryImageConversionException(
        storyRejectionMessage(StoryMediaRejection.unavailable),
      );
    }

    final StoryImageFormat format = detectStoryImageFormat(
      await _readHeader(source),
      fileName: sourcePath,
    );
    final bool tooBig =
        sourceWidth > 0 && sourceWidth * sourceHeight > maxSourcePixels;
    if (!storyImageNeedsNativeDecode(format) && !tooBig) return sourcePath;

    final Directory dir = await _resolveWorkDirectory();
    await dir.create(recursive: true);
    await _sweep(dir);
    final String targetPath =
        '${dir.path}${Platform.pathSeparator}${storyConvertedFileName(sourcePath)}';
    // Se borra ANTES de convertir para que "existe y pesa algo" pruebe de verdad
    // que lo ha escrito esta llamada: si no, un sobrante de una conversión
    // anterior con el mismo nombre pasaría por resultado bueno.
    await _deleteQuietly(File(targetPath));

    final StoryTranscodeBox box = storyTranscodeBox(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    final String? result;
    try {
      result = await _transcode(sourcePath, targetPath, box.width, box.height);
    } catch (error) {
      throw StoryImageConversionException(
        _failureMessage(format, error),
        cause: error,
      );
    }
    if (result == null) {
      // El contrato del typedef: null es "el sistema tampoco supo leerla".
      throw StoryImageConversionException(_failureMessage(format, null));
    }
    final File converted = File(result);
    if (!await converted.exists() || await converted.length() == 0) {
      // No es un problema de formato (el sistema no ha dicho que no sepa leerla):
      // no ha llegado a escribir, y eso suele ser espacio o permisos.
      throw const StoryImageConversionException(_retryMessage);
    }
    return result;
  }

  Future<Directory> _resolveWorkDirectory() async {
    final Directory? injected = _workDirectory;
    if (injected != null) return injected;
    final Directory base = await getTemporaryDirectory();
    return Directory(
      '${base.path}${Platform.pathSeparator}$workDirectoryName',
    );
  }

  /// Barre los convertidos viejos.
  ///
  /// Se hace aquí y no al abrir el compositor porque esta es la única función
  /// que crea basura: si nunca se convierte, no hay nada que limpiar.
  Future<void> _sweep(Directory dir) async {
    try {
      final DateTime cutoff = DateTime.now().subtract(_keepConverted);
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final FileStat stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await _deleteQuietly(entity);
      }
    } catch (_) {
      // Limpiar es higiene, no parte de publicar: si falla, se publica igual.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ídem: no se aborta una publicación porque no se pueda borrar un temporal.
    }
  }

  Future<List<int>> _readHeader(File file) async {
    try {
      final RandomAccessFile handle = await file.open();
      try {
        return await handle.read(kStoryImageHeaderBytes);
      } finally {
        await handle.close();
      }
    } catch (_) {
      // Sin cabecera se decide por el nombre. No es motivo para abortar: puede
      // ser un fichero de iCloud a medio bajar y aún así el transcodificador
      // nativo tiene algo que decir.
      return const <int>[];
    }
  }
}

/// Lo que se dice cuando el fallo NO es del formato y reintentar puede arreglarlo.
const String _retryMessage =
    'No hemos podido preparar esta foto. Vuelve a intentarlo; si sigue fallando, '
    'comprueba que te queda espacio libre en el teléfono.';

/// Qué se le dice a la persona cuando el transcodificador no ha podido.
///
/// Se mira POR QUÉ falló, no solo qué formato era: el disco lleno, el canal
/// nativo caído o un fichero de iCloud a medio bajar son fallos TRANSITORIOS, y
/// contestarles con el discurso del HEIC ("cambia el ajuste de la cámara", "haz
/// una captura y publica esa") es dar un consejo permanente —y que además degrada
/// la foto— para algo que se arregla reintentando.
String _failureMessage(StoryImageFormat format, Object? error) {
  if (error != null && !_isFormatFailure(error)) return _retryMessage;
  if (format == StoryImageFormat.heif) {
    return 'Esta foto está en HEIC y no hemos podido convertirla. Si es un '
        'iPhone, en Ajustes → Cámara → Formatos elige "Más compatible" para las '
        'próximas; para esta, haz una captura de pantalla y publica esa.';
  }
  return 'No hemos podido leer esta foto: no reconocemos su formato. Prueba con '
      'otra, o haz una captura de pantalla de esta y publica esa.';
}

/// ¿El sistema ha dicho que no sabe leer ESTA imagen?
///
/// `CompressError.code` trae el motivo del lado nativo. Solo `decode_failed` y
/// `unsupported_format` son del fichero; `io_failed` y `unknown` (y cualquier
/// excepción ajena, como un MissingPluginException) son del momento.
bool _isFormatFailure(Object error) {
  if (error is! CompressError) return false;
  return error.code == 'decode_failed' || error.code == 'unsupported_format';
}

/// Transcodificación real.
///
/// Se eligió `flutter_image_compress` (y no las miniaturas de `photo_manager`)
/// porque conserva la proporción: escala con un único factor para ancho y alto y
/// nunca amplía. Las miniaturas de `photo_manager` piden a iOS
/// `PHImageContentModeAspectFill`, que RECORTA lo que sobra para llenar la caja:
/// una foto 4:3 en una caja cuadrada volvería recortada a cuadrado.
Future<String?> _compressToJpeg(
  String sourcePath,
  String targetPath,
  int maxWidth,
  int maxHeight,
) async {
  final XFile? out = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    targetPath,
    minWidth: maxWidth,
    minHeight: maxHeight,
    // 95 y no 85: esto NO es la compresión final. StoryService reencoda después
    // a calidad 85, y comprimir fuerte dos veces se nota en la cara y el pelo.
    quality: 95,
    format: CompressFormat.jpeg,
    // keepExif en false a propósito: el transcodificador ya deja los píxeles
    // derechos, así que conservar la etiqueta de orientación original haría que
    // `img.bakeOrientation` de StoryService la girase OTRA vez. De paso, no se
    // publica el GPS de la foto.
    keepExif: false,
  );
  return out?.path;
}
