import 'dart:typed_data';

import 'package:attra/src/features/stories/domain/selfie_mirror.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// El selfie salía EN ESPEJO: el plugin de iOS marca la conexión de la cámara
/// frontal como reflejada (camera_avfoundation, DefaultCamera.swift:158). En la
/// vista previa eso es lo natural —un espejo—, pero en la foto guardada no: el
/// texto sale al revés y la cara no es la que ve el resto del mundo. Instagram
/// previsualiza en espejo y guarda la foto normal.
///
/// Los tests pintan imágenes ASIMÉTRICAS a propósito: una simétrica pasaría
/// aunque el volteo no hiciera nada.
Uint8List _asymmetricJpeg({int width = 8, int height = 4}) {
  final img.Image image = img.Image(width: width, height: height);
  // Mitad izquierda roja, mitad derecha azul: si se voltea, los lados cambian.
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixel(
        x,
        y,
        x < width ~/ 2
            ? img.ColorRgb8(255, 0, 0)
            : img.ColorRgb8(0, 0, 255),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

/// ¿El píxel de la izquierda es rojo?
bool _leftIsRed(Uint8List bytes) {
  final img.Image decoded = img.decodeImage(bytes)!;
  final img.Pixel p = decoded.getPixel(0, decoded.height ~/ 2);
  return p.r > 200 && p.b < 60;
}

void main() {
  group('Cuándo se deshace el espejo', () {
    test('cámara frontal en una plataforma que refleja: SÍ', () {
      expect(
        shouldUnmirrorSelfie(isFrontLens: true, platformMirrors: true),
        isTrue,
      );
    });

    test('cámara trasera: NUNCA', () {
      // La trasera no se refleja: voltearla pondría del revés una foto correcta.
      expect(
        shouldUnmirrorSelfie(isFrontLens: false, platformMirrors: true),
        isFalse,
      );
    });

    test('frontal en Android: NO', () {
      // CameraX no refleja la imagen fija. Voltear ahí rompería las fotos que
      // hoy salen bien, que es peor que el fallo que se venía a arreglar.
      expect(
        shouldUnmirrorSelfie(isFrontLens: true, platformMirrors: false),
        isFalse,
      );
    });
  });

  group('El volteo de verdad', () {
    test('los lados se intercambian', () {
      final Uint8List original = _asymmetricJpeg();
      expect(_leftIsRed(original), isTrue, reason: 'punto de partida');

      final Uint8List? flipped = unmirrorImageBytes(original);

      expect(flipped, isNotNull);
      expect(
        _leftIsRed(flipped!),
        isFalse,
        reason: 'tras deshacer el espejo, el rojo tiene que estar a la derecha',
      );
    });

    test('voltear dos veces devuelve la imagen de partida', () {
      // Comprobación de que el volteo es exactamente eso y no una rotación ni
      // un recorte disfrazado.
      final Uint8List original = _asymmetricJpeg();
      final Uint8List doble =
          unmirrorImageBytes(unmirrorImageBytes(original)!)!;

      expect(_leftIsRed(doble), isTrue);
    });

    test('las dimensiones no cambian', () {
      // Un volteo horizontal no puede alterar el tamaño: si cambia, es que se
      // está rotando, que es justo el otro fallo de esta pantalla.
      final Uint8List original = _asymmetricJpeg(width: 12, height: 5);
      final img.Image antes = img.decodeImage(original)!;
      final img.Image despues = img.decodeImage(unmirrorImageBytes(original)!)!;

      expect(despues.width, antes.width);
      expect(despues.height, antes.height);
    });
  });

  group('Cuando no se puede', () {
    test('bytes ilegibles devuelven null en vez de reventar', () {
      // Quien llama se queda con la foto original: una foto en espejo es
      // infinitamente mejor que ninguna foto.
      expect(
        unmirrorImageBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
        isNull,
      );
    });

    test('bytes vacíos devuelven null', () {
      expect(unmirrorImageBytes(Uint8List(0)), isNull);
    });

    test('el resultado sigue siendo una imagen decodificable', () {
      // Si saliera un JPEG corrupto, el fallo aparecería mucho más tarde, al
      // subirlo, y con un mensaje que no señala a este código.
      final Uint8List? out = unmirrorImageBytes(_asymmetricJpeg());
      expect(img.decodeImage(out!), isNotNull);
    });
  });
}
