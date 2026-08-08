import 'dart:io';

import 'package:attra/src/features/stories/data/story_image_conversion.dart';
import 'package:attra/src/features/stories/domain/story_errors.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';

/// El carrete tiene que entregar "un fichero que la app puede procesar".
///
/// El transcodificador de verdad habla por canal nativo (no existe en tests),
/// así que se falsea; lo que se prueba aquí es el resto: cuándo se llama y
/// cuándo no, con qué destino, y qué pasa cuando falla. Los ficheros son reales
/// porque leer la cabecera del disco es justo la parte que no quiero simular.
void main() {
  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('attra_story_conv');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final File f = File('${work.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(bytes);
    return f;
  }

  group('Lo que ya es procesable se deja intacto', () {
    test('un JPEG se sube tal cual, sin recomprimir', () async {
      final File source = write('IMG_0001.jpg', _jpegBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String _, String __, int ___, int ____) async {
          called = true;
          return null;
        },
      );

      expect(await converter.ensureDecodable(source.path), source.path);
      expect(
        called,
        isFalse,
        reason: 'reencodar un JPEG pierde calidad sin ganar nada',
      );
    });

    test('un PNG (captura de pantalla) se sube tal cual', () async {
      final File source = write('captura.png', _pngBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String _, String __, int ___, int ____) async {
          called = true;
          return null;
        },
      );

      expect(await converter.ensureDecodable(source.path), source.path);
      expect(
        called,
        isFalse,
        reason: 'una captura con texto se ve peor pasada por JPEG',
      );
    });

    test('el nombre no manda: un JPEG llamado .heic tampoco se convierte',
        () async {
      final File source = write('IMG_0002.heic', _jpegBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String _, String __, int ___, int ____) async {
          called = true;
          return null;
        },
      );

      expect(await converter.ensureDecodable(source.path), source.path);
      expect(called, isFalse);
    });
  });

  group('Lo que la app no sabe leer se convierte', () {
    test('un HEIC se transcodifica y se devuelve el resultado', () async {
      final File source = write('IMG_0042.HEIC', _heicBytes);
      String? seenSource;
      String? seenTarget;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          seenSource = from;
          seenTarget = to;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      final String result = await converter.ensureDecodable(source.path);

      expect(seenSource, source.path);
      expect(seenTarget, endsWith('IMG_0042_attra.jpg'));
      expect(result, seenTarget);
      expect(File(result).existsSync(), isTrue);
    });

    test('el destino nunca es el fichero de origen', () async {
      // El transcodificador nativo se niega a escribir sobre su entrada.
      final File source = write('IMG_0003.jpg', _heicBytes);
      String? seenTarget;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          seenTarget = to;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(source.path);
      expect(seenTarget, isNot(source.path));
    });

    test('un formato desconocido tambien se intenta convertir', () async {
      // Si no reconocemos los bytes, el decodificador de Dart tampoco: el del
      // sistema es el último cartucho antes de rendirse.
      final File source = write('raro.xyz', <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          called = true;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(source.path);
      expect(called, isTrue);
    });

    test('crea el directorio de trabajo si no existe', () async {
      final Directory missing = Directory(
        '${work.path}${Platform.pathSeparator}sub',
      );
      final File source = write('IMG_0004.HEIC', _heicBytes);
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: missing,
        transcode: (String from, String to, int _, int __) async {
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(source.path);
      expect(missing.existsSync(), isTrue);
    });
  });

  group('Cuando falla, lo dice', () {
    Future<StoryImageConversionException> failureOf(
      File source,
      StoryImageTranscoder transcode,
    ) async {
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: transcode,
      );
      try {
        await converter.ensureDecodable(source.path);
      } on StoryImageConversionException catch (e) {
        return e;
      }
      fail('tenía que haber fallado');
    }

    test('si el sistema no puede, el mensaje explica el HEIC y que hacer',
        () async {
      final File source = write('IMG_0005.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async => null,
      );

      expect(error.message, contains('HEIC'));
      expect(error.message, contains('captura'));
      expect(
        error.message,
        isNot(contains('StoryImageConversionException')),
        reason: 'el texto es para la persona, no un volcado',
      );
    });

    test('un formato desconocido no promete un arreglo de HEIC', () async {
      final File source = write('raro.xyz', <int>[9, 9, 9, 9, 9, 9, 9, 9]);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async => null,
      );

      expect(error.message, isNot(contains('HEIC')));
      expect(error.message, contains('formato'));
    });

    test('si el transcodificador revienta, el fallo no se pierde', () async {
      final File source = write('IMG_0006.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async =>
            throw StateError('canal nativo caido'),
      );

      expect(error.message, isNotEmpty);
      expect(
        error.cause.toString(),
        contains('canal nativo caido'),
        reason: 'el detalle técnico se guarda para los logs',
      );
      expect(error.toString(), contains('canal nativo caido'));
    });

    test('una ruta devuelta sin fichero detras no se da por buena', () async {
      // Seguro ante un cambio del plugin: hoy `flutter_image_compress` solo
      // responde con la ruta si el `writeToURL:` nativo devolvió YES, así que
      // esto no debería pasar. Si pasara, subiríamos un fichero fantasma.
      final File source = write('IMG_0007.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String to, int ___, int ____) async => to,
      );

      expect(error.message, isNotEmpty);
      expect(
        error.message,
        isNot(contains('HEIC')),
        reason: 'no ha fallado por el formato: no ha llegado a escribir',
      );
    });

    test('un sobrante de una conversion anterior no pasa por resultado',
        () async {
      // El destino se borra ANTES de convertir justo para esto: si no, "existe y
      // pesa algo" se cumpliría con el fichero de la vez anterior.
      final File source = write('IMG_0010.HEIC', _heicBytes);
      final File leftover = write('IMG_0010_attra.jpg', _jpegBytes);
      expect(leftover.existsSync(), isTrue);

      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String to, int ___, int ____) async => to,
      );

      expect(error.message, isNotEmpty);
      expect(leftover.existsSync(), isFalse);
    });

    test('un resultado vacio se detecta', () async {
      final File source = write('IMG_0008.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String to, int ___, int ____) async {
          File(to).writeAsBytesSync(const <int>[]);
          return to;
        },
      );

      expect(error.message, isNotEmpty);
    });

    test('un fallo de disco NO se cuenta como problema de formato', () async {
      // Sin espacio libre, iOS responde `io_failed`. Contestar con "cambia el
      // ajuste de la cámara" y "publica una captura" es dar un consejo
      // permanente —y que degrada la foto— para algo que se arregla solo.
      final File source = write('IMG_0011.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async =>
            throw CompressError('no space left', code: 'io_failed'),
      );

      expect(error.message, isNot(contains('HEIC')));
      expect(error.message, isNot(contains('captura')));
      expect(error.message.toLowerCase(), contains('intent'));
    });

    test('el canal nativo caido tampoco es un problema de formato', () async {
      final File source = write('IMG_0012.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async =>
            throw StateError('MissingPluginException'),
      );

      expect(error.message, isNot(contains('HEIC')));
      expect(error.cause, isA<StateError>());
    });

    test('si el sistema dice que no sabe leerla, ahi si es el formato',
        () async {
      final File source = write('IMG_0013.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async =>
            throw CompressError('not decodable', code: 'decode_failed'),
      );

      expect(error.message, contains('HEIC'));
    });

    test('si el fichero ya no esta, se dice eso y no otra cosa', () async {
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String _, String __, int ___, int ____) async =>
            fail('no hay nada que convertir'),
      );

      await expectLater(
        converter.ensureDecodable(
          '${work.path}${Platform.pathSeparator}no_existe.HEIC',
        ),
        throwsA(
          isA<StoryImageConversionException>().having(
            (StoryImageConversionException e) => e.message,
            'message',
            contains('borrado'),
          ),
        ),
      );
    });

    test('un DNG de ProRAW pasa por el conversor', () async {
      // Un DNG empieza por la firma TIFF y el paquete `image` lo reclama, pero
      // lo que decodifica es la vista previa reducida: se publicaría una
      // miniatura. iOS sí sabe leerlo, así que va al transcodificador.
      final File source = write('IMG_0014.dng', _tiffBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          called = true;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(source.path);
      expect(called, isTrue);
    });

    test('el error trae texto presentable a la persona', () async {
      final File source = write('IMG_0009.HEIC', _heicBytes);
      final StoryImageConversionException error = await failureOf(
        source,
        (String _, String __, int ___, int ____) async => null,
      );

      expect(error, isA<StoryUserFacingError>());
      expect(storyPublishFailureMessage(error), error.message);
    });
  });

  group('Tamano de salida', () {
    test('el lado LARGO se deja en 1920, no el corto', () {
      // `flutter_image_compress` escala para CUBRIR la caja: un cuadrado
      // 1920x1920 deja el lado corto en 1920 y el largo por encima, y entonces
      // StoryService tiene que volver a reducir en Dart. Dos reescalados
      // encadenados, y el segundo por vecino mas cercano.
      final StoryTranscodeBox box = storyTranscodeBox(
        sourceWidth: 3024,
        sourceHeight: 4032,
      );

      expect(box.height, 1920);
      expect(box.width, 1440);
    });

    test('una panoramica tampoco se cuela', () {
      final StoryTranscodeBox box = storyTranscodeBox(
        sourceWidth: 10000,
        sourceHeight: 2500,
      );

      expect(box.width, 1920);
      expect(box.height, 480);
    });

    test('nunca amplia una foto pequena', () {
      final StoryTranscodeBox box = storyTranscodeBox(
        sourceWidth: 800,
        sourceHeight: 600,
      );

      expect(box.width, 800);
      expect(box.height, 600);
    });

    test('sin tamano conocido se cae a la caja cuadrada de antes', () {
      final StoryTranscodeBox box = storyTranscodeBox(
        sourceWidth: 0,
        sourceHeight: 0,
      );

      expect(box.width, StoryImageConverter.maxSide);
      expect(box.height, StoryImageConverter.maxSide);
    });

    test('el tamano pedido llega al transcodificador', () async {
      final File source = write('IMG_0020.HEIC', _heicBytes);
      int? seenWidth;
      int? seenHeight;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int w, int h) async {
          seenWidth = w;
          seenHeight = h;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(
        source.path,
        sourceWidth: 4032,
        sourceHeight: 3024,
      );

      expect(seenWidth, 1920);
      expect(seenHeight, 1440);
    });
  });

  group('Fotos desmesuradas', () {
    test('un JPEG de 24 MP se baja aunque el formato ya fuera legible',
        () async {
      // Decodificar 24 MP en Dart son ~98 MB de mapa de bits, otros tantos para
      // `bakeOrientation`, y todo en el isolate de la interfaz: la pantalla se
      // queda congelada varios segundos y en un movil justo de memoria se muere.
      final File source = write('IMG_0021.jpg', _jpegBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          called = true;
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(
        source.path,
        sourceWidth: 5712,
        sourceHeight: 4284,
      );

      expect(called, isTrue);
    });

    test('un JPEG normal sigue sin tocarse', () async {
      final File source = write('IMG_0022.jpg', _jpegBytes);
      bool called = false;
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          called = true;
          return to;
        },
      );

      expect(
        await converter.ensureDecodable(
          source.path,
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        source.path,
      );
      expect(called, isFalse);
    });
  });

  group('Limpieza del temporal', () {
    test('los convertidos viejos se barren', () async {
      // Cada historia dejaba un JPEG de 1-3 MB en el temporal y no lo borraba
      // nadie: 50 historias son ~200 MB de basura.
      final File old = write('IMG_9999_attra.jpg', _jpegBytes);
      old.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      final File source = write('IMG_0030.HEIC', _heicBytes);
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      await converter.ensureDecodable(source.path);

      expect(old.existsSync(), isFalse);
    });

    test('el convertido recien hecho NO se barre', () async {
      final File source = write('IMG_0031.HEIC', _heicBytes);
      final StoryImageConverter converter = StoryImageConverter(
        workDirectory: work,
        transcode: (String from, String to, int _, int __) async {
          File(to).writeAsBytesSync(_jpegBytes);
          return to;
        },
      );

      final String first = await converter.ensureDecodable(source.path);
      final File other = write('IMG_0032.HEIC', _heicBytes);
      await converter.ensureDecodable(other.path);

      expect(File(first).existsSync(), isTrue);
    });
  });
}

const List<int> _jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46];
const List<int> _pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13,
];
const List<int> _tiffBytes = <int>[0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0];
final List<int> _heicBytes = <int>[
  0x00, 0x00, 0x00, 0x18, //
  ...'ftyp'.codeUnits,
  ...'heic'.codeUnits,
  ...'isom'.codeUnits,
];
