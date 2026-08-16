import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Deshace el efecto espejo de la cámara frontal.
///
/// POR QUÉ HACE FALTA: el plugin de iOS pone `connection.isVideoMirrored = true`
/// cuando la cámara es frontal (camera_avfoundation, DefaultCamera.swift:158).
/// Eso está BIEN para la vista previa —verte reflejado es lo natural, es lo que
/// hace cualquier espejo— pero se cuela también en la foto guardada, y ahí no
/// vale: el texto sale al revés, la raya del pelo cambia de lado y la cara no es
/// la que ve el resto del mundo. Instagram previsualiza en espejo y guarda la
/// foto normal; esto es lo que iguala ese comportamiento.
///
/// Android NO lo necesita: CameraX no refleja la imagen fija. Por eso quien
/// llama decide, y lo hace mirando la plataforma.

/// Voltea horizontalmente una imagen ya codificada.
///
/// Devuelve JPEG. `null` si los bytes no se pueden decodificar, y entonces quien
/// llama debe quedarse con el original: una foto en espejo es mucho mejor que
/// ninguna foto.
Uint8List? unmirrorImageBytes(Uint8List bytes, {int quality = 95}) {
  if (bytes.isEmpty) return null;
  final img.Image? decoded;
  try {
    // `decodeImage` no siempre devuelve null ante basura: con un fichero corto
    // o truncado, alguno de sus decodificadores (el de PSD, por ejemplo) lee
    // mas alla del bufer y LANZA. Sin este try, un fichero a medias tumbaria la
    // captura entera en vez de degradar a "publica la original".
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  // `bakeOrientation` ANTES de voltear: si la foto trae la orientación en EXIF,
  // voltear sobre los píxeles crudos espejaría el eje equivocado (una foto
  // apaisada saldría del revés en vertical).
  final img.Image upright = img.bakeOrientation(decoded);
  final img.Image flipped = img.flipHorizontal(upright);
  return Uint8List.fromList(img.encodeJpg(flipped, quality: quality));
}

/// ¿Hay que deshacer el espejo de esta captura?
///
/// Se decide con dos datos y ninguno más: si la lente es frontal y si la
/// plataforma refleja. Aislado en una función para poder fijarlo con tests, que
/// es lo único que se puede probar de esto sin un móvil delante.
bool shouldUnmirrorSelfie({
  required bool isFrontLens,
  required bool platformMirrors,
}) =>
    isFrontLens && platformMirrors;
