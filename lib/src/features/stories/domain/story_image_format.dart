/// Qué formato de imagen tiene realmente un fichero del carrete.
///
/// POR QUÉ existe esto: publicar una historia desde la galería del iPhone
/// fallaba con "No se pudo procesar la imagen". El punto exacto era
/// `img.decodeImage(bytes)` devolviendo null en StoryService, porque el paquete
/// `image` de Dart NO sabe leer HEIC/HEIF y HEIC es el formato por defecto de la
/// cámara del iPhone.
///
/// Es un fallo NUEVO del compositor: `photo_manager.originFile` devuelve el
/// fichero ORIGINAL (HEIC), mientras que el editor anterior usaba `image_picker`
/// que convierte HEIC a JPEG por su cuenta y tapaba el problema.
///
/// Esto vive en `domain` y no toca ni ficheros ni canales nativos a propósito:
/// es la única parte de la corrección que se puede probar entera.
library;

/// Formato reconocido a partir de los bytes del fichero.
enum StoryImageFormat {
  jpeg,
  png,
  gif,
  webp,
  bmp,

  /// TIFF y todo lo que empieza como TIFF, que incluye el DNG de Apple ProRAW.
  tiff,

  /// HEIC, HEIF, AVIF… cualquier contenedor ISO-BMFF. El paquete `image` no sabe
  /// leer ninguno.
  heif,

  /// Ni los bytes ni el nombre dicen nada reconocible.
  unknown,
}

/// Bytes que hay que leer del principio del fichero para decidir.
///
/// 16 llegan para el más largo de los reconocimientos (RIFF/WEBP mira hasta el
/// byte 12). Se lee solo la cabecera y no el fichero entero porque un HEIC de
/// 12 MP son varios MB que no hacen falta para saber qué es.
const int kStoryImageHeaderBytes = 16;

/// Qué es este fichero.
///
/// Manda el CONTENIDO: el nombre solo se mira si los bytes no dicen nada (por
/// ejemplo si la cabecera venía vacía). Una extensión puede mentir y lo que
/// decide si el decodificador de Dart va a funcionar son los bytes.
StoryImageFormat detectStoryImageFormat(
  List<int> header, {
  String fileName = '',
}) {
  final StoryImageFormat byContent = _byMagicNumber(header);
  if (byContent != StoryImageFormat.unknown) return byContent;
  return _byExtension(fileName);
}

/// ¿Hay que pasar por el decodificador del sistema antes de tocar esta imagen?
///
/// Solo se convierte lo que la app NO puede leer. Un JPEG que se reencoda pierde
/// calidad sin ganar nada, y una captura de pantalla PNG llena de texto se ve
/// peor pasada por JPEG: convertir "por si acaso" degradaría lo que hoy
/// funciona.
///
/// `unknown` sí se convierte: si no reconocemos los bytes, el decodificador de
/// Dart tampoco los va a reconocer, y el del sistema es el único cartucho que
/// queda antes de rendirse.
///
/// `tiff` TAMBIÉN se convierte, aunque el paquete `image` diga que sabe leerlo:
/// un DNG de Apple ProRAW empieza por la misma firma TIFF (`II*\0`) y
/// `TiffDecoder.isValidFile` solo mira esa cabecera, así que lo reclama. Lo que
/// devuelve entonces es el IFD 0, que en un DNG es la vista PREVIA reducida, no
/// la foto: se publicaría una miniatura creyendo que es la imagen. Y si el tile
/// va comprimido de una forma que no soporta, lanza en vez de devolver null. Los
/// TIFF de verdad en un carrete de móvil son prácticamente inexistentes, así que
/// reencodarlos no cuesta nada; publicar una previsualización sí.
bool storyImageNeedsNativeDecode(StoryImageFormat format) {
  switch (format) {
    case StoryImageFormat.jpeg:
    case StoryImageFormat.png:
    case StoryImageFormat.gif:
    case StoryImageFormat.webp:
    case StoryImageFormat.bmp:
      return false;
    case StoryImageFormat.tiff:
    case StoryImageFormat.heif:
    case StoryImageFormat.unknown:
      return true;
  }
}

/// Cómo se llama el fichero convertido.
///
/// Lleva sufijo `_attra` y no solo la extensión cambiada porque el
/// transcodificador se niega a escribir sobre el fichero de origen, y un fichero
/// mal nombrado (bytes irreconocibles dentro de un `.jpg`) acabaría pidiendo
/// justo eso.
String storyConvertedFileName(String sourcePath) {
  final String base = _baseName(sourcePath);
  final int dot = base.lastIndexOf('.');
  final String stem = dot > 0 ? base.substring(0, dot) : base;
  // Sin nombre utilizable se usa uno fijo: es un fichero temporal nuestro, lo
  // único que importa es que exista y termine en .jpg.
  return '${stem.isEmpty ? 'historia' : stem}_attra.jpg';
}

// ---------------------------------------------------------------------------

StoryImageFormat _byMagicNumber(List<int> header) {
  if (_matchesAt(header, 0, const <int>[0xFF, 0xD8, 0xFF])) {
    return StoryImageFormat.jpeg;
  }
  if (_matchesAt(
    header,
    0,
    const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  )) {
    return StoryImageFormat.png;
  }
  if (_matchesAt(header, 0, _ascii('GIF8'))) return StoryImageFormat.gif;
  if (_matchesAt(header, 0, _ascii('RIFF')) &&
      _matchesAt(header, 8, _ascii('WEBP'))) {
    return StoryImageFormat.webp;
  }
  if (_matchesAt(header, 0, _ascii('BM'))) return StoryImageFormat.bmp;
  if (_matchesAt(header, 0, const <int>[0x49, 0x49, 0x2A, 0x00]) ||
      _matchesAt(header, 0, const <int>[0x4D, 0x4D, 0x00, 0x2A])) {
    return StoryImageFormat.tiff;
  }
  // Todo contenedor ISO-BMFF lleva 'ftyp' en los bytes 4..8. NO se filtra por
  // marca concreta (heic/heix/mif1/avif…) a propósito: el paquete `image` no
  // sabe leer ninguna, así que todas tienen que ir por el mismo camino, y una
  // marca nueva de un iPhone futuro no puede volver a romper esto en silencio.
  if (_matchesAt(header, 4, _ascii('ftyp'))) return StoryImageFormat.heif;
  return StoryImageFormat.unknown;
}

StoryImageFormat _byExtension(String fileName) {
  final String base = _baseName(fileName);
  final int dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return StoryImageFormat.unknown;
  switch (base.substring(dot + 1).toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return StoryImageFormat.jpeg;
    case 'png':
      return StoryImageFormat.png;
    case 'gif':
      return StoryImageFormat.gif;
    case 'webp':
      return StoryImageFormat.webp;
    case 'bmp':
      return StoryImageFormat.bmp;
    case 'tif':
    case 'tiff':
      return StoryImageFormat.tiff;
    case 'heic':
    case 'heif':
    case 'avif':
      return StoryImageFormat.heif;
    default:
      return StoryImageFormat.unknown;
  }
}

/// Último tramo de la ruta. Mira las dos barras porque las rutas de test son de
/// Windows y las del móvil de POSIX.
String _baseName(String path) {
  final int slash = path.lastIndexOf('/');
  final int backslash = path.lastIndexOf(r'\');
  final int cut = slash > backslash ? slash : backslash;
  return cut < 0 ? path : path.substring(cut + 1);
}

bool _matchesAt(List<int> header, int offset, List<int> magic) {
  if (header.length < offset + magic.length) return false;
  for (int i = 0; i < magic.length; i++) {
    if (header[offset + i] != magic[i]) return false;
  }
  return true;
}

List<int> _ascii(String text) => text.codeUnits;
