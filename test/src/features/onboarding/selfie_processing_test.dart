import 'dart:typed_data';

import 'package:attra/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// La selfie de verificación acaba siendo la foto de perfil.
///
/// Antes, si no se podía procesar se subían los bytes ORIGINALES con su
/// extensión real y se seguía como si nada: un HEIC quedaba etiquetado
/// `image/jpeg` de foto de perfil, ilegible para media app. Y con un formato
/// bueno pero sin voltear, la selfie se subía ESPEJADA, que es justo lo que esta
/// función existe para evitar.
void main() {
  test('unos bytes ilegibles devuelven null, no la foto sin tocar', () {
    final Uint8List heic = Uint8List.fromList(<int>[
      0x00, 0x00, 0x00, 0x18, //
      ...'ftyp'.codeUnits,
      ...'heic'.codeUnits,
      ...'isom'.codeUnits,
    ]);

    expect(unmirrorSelfieBytes(heic), isNull);
  });

  test('un PNG truncado tampoco se cuela', () {
    final Uint8List entero = Uint8List.fromList(
      img.encodePng(img.Image(width: 48, height: 48)),
    );

    expect(unmirrorSelfieBytes(Uint8List.sublistView(entero, 0, 40)), isNull);
  });

  test('la selfie sale volteada de verdad', () {
    final img.Image original = img.Image(width: 4, height: 1);
    original.setPixelRgb(0, 0, 255, 0, 0);
    original.setPixelRgb(3, 0, 0, 0, 255);
    final Uint8List entrada = Uint8List.fromList(img.encodePng(original));

    final img.Image salida = img.decodeJpg(unmirrorSelfieBytes(entrada)!)!;

    expect(salida.getPixel(0, 0).b, greaterThan(salida.getPixel(0, 0).r));
    expect(salida.getPixel(3, 0).r, greaterThan(salida.getPixel(3, 0).b));
  });

  test('la selfie no sale tumbada si la orientacion venia en la etiqueta', () {
    final img.Image tumbada = img.Image(width: 40, height: 20);
    tumbada.exif.imageIfd.orientation = 6;
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(tumbada));

    final img.Image salida = img.decodeJpg(unmirrorSelfieBytes(entrada)!)!;

    expect(salida.width, 20);
    expect(salida.height, 40);
  });

  test('la foto de perfil no lleva el GPS de donde se hizo', () {
    final img.Image conGps = img.Image(width: 16, height: 16);
    conGps.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(40, 1);
    final Uint8List entrada = Uint8List.fromList(img.encodeJpg(conGps));

    expect(img.decodeJpg(entrada)!.exif.gpsIfd.isEmpty, isFalse);

    final img.Image salida = img.decodeJpg(unmirrorSelfieBytes(entrada)!)!;

    expect(salida.exif.isEmpty, isTrue);
  });
}
