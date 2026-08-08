import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de cableado del compositor.
///
/// La pantalla no se puede montar en un test: `StoryComposerScreen` exige un
/// `StoryService`, que exige Firestore, Functions y Storage reales, y no hay
/// mocks de Firebase en el proyecto. Así que lo que se vigila es que la pantalla
/// siga DELEGANDO en las piezas que sí están probadas, en vez de volver a hacer
/// el trabajo dentro del `State` donde nadie puede verlo.
///
/// Mismo enfoque que story_entry_point_test.dart, y por el mismo motivo: es la
/// única red que queda sobre el `State`.
void main() {
  final String screen = File(
    'lib/src/features/stories/presentation/story_composer_screen.dart',
  ).readAsStringSync();

  test('elegir del carrete pasa por pickStoryMedia', () {
    expect(
      screen.contains('pickStoryMedia('),
      isTrue,
      reason: 'validar, bajar y convertir dentro del State es exactamente lo '
          'que dejaba la excepción sin coger y la rueda girando para siempre.',
    );
  });

  test('los fallos se traducen antes de enseñarlos', () {
    expect(
      screen.contains('storyPublishFailureMessage('),
      isTrue,
      reason: 'sin esto vuelve el "StoryServiceException(null): ..." en '
          'pantalla.',
    );
  });

  test('ningun aviso interpola el error en crudo', () {
    // `'... $error'` llama a toString() y saca el nombre de la clase.
    expect(
      screen.contains(r'$error'),
      isFalse,
      reason: 'el volcado de la excepción no es un mensaje para la persona.',
    );
  });

  test('abrir el carrete no puede dejar la rueda girando', () {
    // `ensurePermission` y `load` hablan por canal nativo y LANZAN. Sin el
    // finally, `_galleryLoading` se quedaba en true para siempre y la guarda de
    // reentrada bloqueaba cualquier reintento.
    final int abrir = screen.indexOf('Future<void> _openGallery()');
    final int siguiente = screen.indexOf('Future<void>', abrir + 10);
    final String cuerpo = screen.substring(abrir, siguiente);

    expect(cuerpo.contains('try {'), isTrue);
    expect(cuerpo.contains('} finally {'), isTrue);
    expect(cuerpo.contains('_galleryLoading = false'), isTrue);
    expect(
      cuerpo.contains('onError:'),
      isTrue,
      reason: 'una miniatura que no llega no puede tumbar la cuadrícula',
    );
  });

  test('paginar no hace setState en pleno build', () {
    // `_openGallery` hace setState en su primera línea: llamarlo desde el
    // itemBuilder es la pantalla roja de "setState() called during build".
    final int rejilla = screen.indexOf('itemBuilder:');
    final String cuerpo = screen.substring(rejilla, rejilla + 900);

    expect(cuerpo.contains('addPostFrameCallback'), isTrue);
  });

  test('elegir del carrete tiene guarda de reentrada', () {
    // El velo de `_publishing` no absorbe toques hasta el frame siguiente: dos
    // dedos en dos casillas a la vez publicaban DOS historias.
    final int metodo = screen.indexOf('Future<void> _pickFromGallery(');
    final String cuerpo = screen.substring(metodo, metodo + 900);

    expect(cuerpo.contains('if (_publishing) return;'), isTrue);
  });

  test('la galeria es quien garantiza el formato, no el servicio', () {
    final String service = File(
      'lib/src/features/stories/data/story_service.dart',
    ).readAsStringSync();
    // Se miran los IMPORTS y no el texto suelto: el servicio sí puede NOMBRAR al
    // conversor en un comentario que explique dónde vive el arreglo.
    expect(
      service.contains("import 'story_image_conversion.dart'") ||
          service.contains('package:flutter_image_compress'),
      isFalse,
      reason: 'el servicio y el compositor tienen que seguir siendo agnósticos '
          'del formato: quien sabe de formatos del sistema es el origen.',
    );

    final String gallery = File(
      'lib/src/features/stories/data/story_media_sources.dart',
    ).readAsStringSync();
    expect(gallery.contains('ensureDecodable('), isTrue);
  });
}
