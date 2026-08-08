import 'dart:typed_data';

import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:attra/src/features/stories/domain/story_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Lo que le pasa a la foto entre que se elige y se sube.
///
/// Se ejercita la función DE VERDAD con bytes de verdad. La prueba anterior
/// construía la excepción con una copia del texto escrita a mano y se afirmaba a
/// sí misma: seguía en verde aunque alguien devolviera el mensaje mudo.
void main() {
  test('unos bytes que no son una imagen dicen que hacer', () {
    final Uint8List basura = Uint8List.fromList(
      List<int>.generate(512, (int i) => i % 251),
    );

    expect(
      () => processStoryImageBytes(basura),
      throwsA(
        isA<StoryUserMessageException>().having(
          (StoryUserMessageException e) => e.message,
          'message',
          storyUnreadableImageMessage,
        ),
      ),
    );
  });

  test('un PNG truncado tampoco se escapa como error de red', () {
    // Los decodificadores de PNG, JPEG y TIFF LANZAN con datos a medias en vez
    // de devolver null: esa excepción subía cruda hasta el compositor y se
    // enseñaba "Revisa tu conexión" para un problema permanente del fichero.
    final Uint8List entero = Uint8List.fromList(
      img.encodePng(img.Image(width: 64, height: 64)),
    );
    final Uint8List cortado = Uint8List.sublistView(entero, 0, 40);

    expect(
      () => processStoryImageBytes(cortado),
      throwsA(isA<StoryUserMessageException>()),
    );
    // Y el compositor lo enseña como texto, no como volcado.
    try {
      processStoryImageBytes(cortado);
    } catch (error) {
      expect(storyPublishFailureMessage(error), storyUnreadableImageMessage);
    }
  });

  test('la foto sube derecha aunque la orientacion viniera en la etiqueta', () {
    // En Android los píxeles llegan sin rotar y la rotación solo en el EXIF.
    final img.Image tumbada = img.Image(width: 40, height: 20);
    tumbada.exif.imageIfd.orientation = 6;
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(tumbada));

    final img.Image salida = img.decodeJpg(processStoryImageBytes(entrada))!;

    expect(salida.width, 20);
    expect(salida.height, 40);
  });

  test('la historia no se publica con el GPS de donde se hizo la foto', () {
    // `encodeJpg` REESCRIBE el EXIF de la imagen decodificada: re-codificar no
    // quita los metadatos por sí solo, hay que vaciarlos.
    final img.Image conGps = img.Image(width: 32, height: 32);
    conGps.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(40, 1);
    conGps.exif.imageIfd['Model'] = img.IfdValueAscii('iPhone 15 Pro');
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(conGps));

    expect(
      img.decodeJpg(entrada)!.exif.gpsIfd.isEmpty,
      isFalse,
      reason: 'si no, esta prueba no estaría comprobando nada',
    );

    final img.Image salida = img.decodeJpg(processStoryImageBytes(entrada))!;

    expect(salida.exif.gpsIfd.isEmpty, isTrue);
    expect(salida.exif.isEmpty, isTrue);
  });

  test('una foto grande se reduce al tope de 1920', () {
    final Uint8List entrada = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 4000, height: 2000)),
    );

    final img.Image salida = img.decodeJpg(processStoryImageBytes(entrada))!;

    expect(salida.width, 1920);
    expect(salida.height, 960);
  });
}
