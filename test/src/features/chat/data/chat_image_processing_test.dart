import 'dart:typed_data';

import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// La misma ruta de imagen que las historias, pero en el chat.
///
/// El transcodificador nativo se falsea (no hay canal nativo en un test); lo que
/// se prueba es todo lo demás.
void main() {
  Future<Uint8List?> nunca(Uint8List bytes, int maxSide) async => null;

  test('un HEIC que el paquete `image` no lee lo salva el sistema', () async {
    // En Android `image_picker` devuelve el fichero ORIGINAL sin tocar cuando
    // BitmapFactory no supo abrirlo, así que un HEIC recibido por WhatsApp llega
    // aquí entero. Antes acababa en "No se pudo procesar la imagen." y no había
    // manera de mandar esa foto.
    final Uint8List heic = Uint8List.fromList(<int>[
      0x00, 0x00, 0x00, 0x18, //
      ...'ftyp'.codeUnits,
      ...'heic'.codeUnits,
      ...'isom'.codeUnits,
    ]);
    final Uint8List comoLoDejariaElSistema = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 30, height: 20)),
    );
    bool llamado = false;

    final ProcessedChatImage processed = await processChatImageBytes(
      heic,
      transcode: (Uint8List bytes, int maxSide) async {
        llamado = true;
        return comoLoDejariaElSistema;
      },
    );

    expect(llamado, isTrue);
    expect(processed.width, 30);
    expect(processed.height, 20);
  });

  test('si tampoco puede el sistema, se dice que hacer', () async {
    final Uint8List basura = Uint8List.fromList(
      List<int>.generate(256, (int i) => i),
    );

    expect(
      () => processChatImageBytes(basura, transcode: nunca),
      throwsA(
        isA<ChatServiceException>().having(
          (ChatServiceException e) => e.message,
          'message',
          chatUnreadableImageMessage,
        ),
      ),
    );
  });

  test('un PNG truncado no revienta con ImageException', () async {
    final Uint8List entero = Uint8List.fromList(
      img.encodePng(img.Image(width: 64, height: 64)),
    );
    final Uint8List cortado = Uint8List.sublistView(entero, 0, 40);

    expect(
      () => processChatImageBytes(cortado, transcode: nunca),
      throwsA(isA<ChatServiceException>()),
    );
  });

  test('la foto llega derecha al chat, no tumbada', () async {
    // En Android los píxeles vienen sin rotar y la rotación solo en el EXIF: al
    // vaciar los metadatos había que dejar antes los píxeles ya derechos.
    final img.Image tumbada = img.Image(width: 40, height: 20);
    tumbada.exif.imageIfd.orientation = 6;
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(tumbada));

    final ProcessedChatImage processed = await processChatImageBytes(
      entrada,
      transcode: nunca,
    );

    expect(processed.width, 20);
    expect(processed.height, 40);
  });

  test('mandar una foto no es mandar donde vives', () async {
    // El comentario del servicio presumía de que re-codificar quita el EXIF.
    // No lo quita: `encodeJpg` lo REESCRIBE, GPS incluido.
    final img.Image conGps = img.Image(width: 32, height: 32);
    conGps.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational(3, 1);
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(conGps));

    expect(img.decodeJpg(entrada)!.exif.gpsIfd.isEmpty, isFalse);

    final ProcessedChatImage processed = await processChatImageBytes(
      entrada,
      transcode: nunca,
    );

    expect(img.decodeJpg(processed.bytes)!.exif.isEmpty, isTrue);
  });
}
