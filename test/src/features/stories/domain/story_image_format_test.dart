import 'package:attra/src/features/stories/domain/story_image_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detección de formato del carrete.
///
/// Lo que se rompió: publicar una historia desde la galería del iPhone fallaba
/// con "No se pudo procesar la imagen" porque `img.decodeImage` devolvía null
/// ante un HEIC, el formato por defecto de la cámara del iPhone. Esta es la
/// pieza que decide qué hay que convertir y qué NO hay que tocar.
void main() {
  group('Reconocer por los bytes', () {
    test('JPEG', () {
      expect(detectStoryImageFormat(_jpeg), StoryImageFormat.jpeg);
    });

    test('PNG', () {
      expect(detectStoryImageFormat(_png), StoryImageFormat.png);
    });

    test('GIF', () {
      expect(detectStoryImageFormat(_gif), StoryImageFormat.gif);
    });

    test('WebP (RIFF con la marca en el byte 8)', () {
      expect(detectStoryImageFormat(_webp), StoryImageFormat.webp);
    });

    test('un RIFF que NO es WebP no se confunde con uno', () {
      // Un WAV empieza igual: si solo se mirasen los cuatro primeros bytes,
      // cualquier RIFF pasaría por imagen legible y se subiría basura.
      final List<int> wav = <int>[
        ...'RIFF'.codeUnits,
        0, 0, 0, 0, //
        ...'WAVE'.codeUnits,
        0, 0, 0, 0, //
      ];
      expect(detectStoryImageFormat(wav), StoryImageFormat.unknown);
    });

    test('BMP', () {
      expect(detectStoryImageFormat(_bmp), StoryImageFormat.bmp);
    });

    test('TIFF en los dos ordenes de byte', () {
      expect(
        detectStoryImageFormat(<int>[0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0]),
        StoryImageFormat.tiff,
      );
      expect(
        detectStoryImageFormat(<int>[0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8]),
        StoryImageFormat.tiff,
      );
    });

    test('HEIC de la camara del iPhone', () {
      expect(detectStoryImageFormat(_heic), StoryImageFormat.heif);
    });

    test('cualquier marca ISO-BMFF cuenta, no solo "heic"', () {
      // A propósito no se filtra por marca: `image` no sabe leer NINGÚN
      // contenedor ISO-BMFF, y una marca nueva de un iPhone futuro no puede
      // volver a colarse hasta romper la publicación.
      for (final String brand in <String>[
        'heic',
        'heix',
        'hevc',
        'mif1',
        'msf1',
        'avif',
      ]) {
        expect(
          detectStoryImageFormat(_isoBmff(brand)),
          StoryImageFormat.heif,
          reason: 'la marca $brand también hay que convertirla',
        );
      }
    });
  });

  group('El nombre solo decide si los bytes no dicen nada', () {
    test('sin cabecera se cae a la extension', () {
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/IMG_0042.HEIC'),
        StoryImageFormat.heif,
      );
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/IMG_0042.jpg'),
        StoryImageFormat.jpeg,
      );
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/captura.PNG'),
        StoryImageFormat.png,
      );
    });

    test('los bytes ganan a la extension cuando el nombre miente', () {
      // Un HEIC llamado .jpg tiene que convertirse igual: si mandase el nombre,
      // volveríamos al fallo original.
      expect(
        detectStoryImageFormat(_heic, fileName: '/tmp/IMG_0042.jpg'),
        StoryImageFormat.heif,
      );
      // Y al revés: un JPEG llamado .heic NO se toca, para no recomprimirlo sin
      // motivo.
      expect(
        detectStoryImageFormat(_jpeg, fileName: '/tmp/IMG_0042.heic'),
        StoryImageFormat.jpeg,
      );
    });

    test('un punto en una carpeta no se confunde con la extension', () {
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/v1.2/IMG_0042'),
        StoryImageFormat.unknown,
      );
    });

    test('sin bytes ni extension util queda desconocido', () {
      expect(detectStoryImageFormat(const <int>[]), StoryImageFormat.unknown);
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/IMG_0042'),
        StoryImageFormat.unknown,
      );
      expect(
        detectStoryImageFormat(const <int>[], fileName: '/tmp/IMG_0042.'),
        StoryImageFormat.unknown,
      );
    });

    test('una cabecera mas corta que la firma no revienta', () {
      // Pasa de verdad con un fichero de iCloud a medio bajar.
      expect(detectStoryImageFormat(const <int>[0xFF]), StoryImageFormat.unknown);
      expect(
        detectStoryImageFormat(const <int>[0x89, 0x50, 0x4E]),
        StoryImageFormat.unknown,
      );
    });
  });

  group('Que se convierte y que se deja en paz', () {
    test('lo que la app ya sabe leer NO se toca', () {
      // Reencodar un JPEG pierde calidad sin ganar nada, y una captura PNG con
      // texto se ve peor pasada por JPEG.
      for (final StoryImageFormat format in <StoryImageFormat>[
        StoryImageFormat.jpeg,
        StoryImageFormat.png,
        StoryImageFormat.gif,
        StoryImageFormat.webp,
        StoryImageFormat.bmp,
      ]) {
        expect(
          storyImageNeedsNativeDecode(format),
          isFalse,
          reason: '$format ya lo decodifica el paquete `image`',
        );
      }
    });

    test('HEIF y lo desconocido pasan por el decodificador del sistema', () {
      expect(storyImageNeedsNativeDecode(StoryImageFormat.heif), isTrue);
      expect(storyImageNeedsNativeDecode(StoryImageFormat.unknown), isTrue);
    });

    test('un DNG de ProRAW no se le deja al paquete `image`', () {
      // Un DNG empieza por la firma TIFF, y `TiffDecoder.isValidFile` solo mira
      // esa cabecera: lo reclama y devuelve el IFD 0, que en un DNG es la vista
      // PREVIA reducida. Se publicaría una miniatura creyendo que es la foto.
      final StoryImageFormat dng = detectStoryImageFormat(
        <int>[0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0],
        fileName: '/tmp/IMG_0042.dng',
      );
      expect(dng, StoryImageFormat.tiff);
      expect(storyImageNeedsNativeDecode(dng), isTrue);
    });

    test('todo formato del enum tiene decision, ninguno se queda a medias', () {
      for (final StoryImageFormat format in StoryImageFormat.values) {
        expect(() => storyImageNeedsNativeDecode(format), returnsNormally);
      }
    });
  });

  group('Nombre del fichero convertido', () {
    test('conserva el nombre y acaba en .jpg', () {
      expect(
        storyConvertedFileName('/var/tmp/IMG_0042.HEIC'),
        'IMG_0042_attra.jpg',
      );
    });

    test('vale con rutas de Windows (las de los tests)', () {
      expect(
        storyConvertedFileName(r'C:\Users\a\IMG_0042.heic'),
        'IMG_0042_attra.jpg',
      );
    });

    test('sin extension tambien', () {
      expect(storyConvertedFileName('/var/tmp/IMG_0042'), 'IMG_0042_attra.jpg');
    });

    test('nunca coincide con el nombre de origen', () {
      // El transcodificador se niega a escribir sobre su propia entrada, así que
      // un fichero mal nombrado (bytes irreconocibles en un .jpg) no puede
      // acabar pidiendo origen y destino iguales.
      for (final String path in <String>[
        '/tmp/IMG.jpg',
        '/tmp/IMG.jpeg',
        '/tmp/IMG_attra.jpg',
        '/tmp/',
        '',
      ]) {
        final String name = storyConvertedFileName(path);
        expect(name.endsWith('.jpg'), isTrue, reason: 'destino de $path');
        expect(path.endsWith('/$name'), isFalse, reason: 'destino de $path');
        expect(name, isNot('.jpg'), reason: 'destino de $path');
      }
    });
  });
}

const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46];
const List<int> _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13,
];
final List<int> _gif = <int>[...'GIF89a'.codeUnits, 1, 0, 1, 0];
final List<int> _webp = <int>[
  ...'RIFF'.codeUnits,
  0, 0, 0, 0, //
  ...'WEBP'.codeUnits,
  ...'VP8 '.codeUnits,
];
final List<int> _bmp = <int>[...'BM'.codeUnits, 0, 0, 0, 0, 0, 0];
final List<int> _heic = _isoBmff('heic');

/// Cabecera de un contenedor ISO-BMFF: tamaño de caja, 'ftyp' y la marca.
List<int> _isoBmff(String brand) => <int>[
      0x00, 0x00, 0x00, 0x18, //
      ...'ftyp'.codeUnits,
      ...brand.codeUnits,
      ...'isom'.codeUnits,
    ];
