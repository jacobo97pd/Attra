import 'package:attra/src/features/stories/data/story_image_conversion.dart';
import 'package:attra/src/features/stories/data/story_media_sources.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/domain/story_composer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Elegir del carrete, con todas sus formas de fallar.
///
/// Esto vivía dentro del `State` de la pantalla, donde no se podía probar: por
/// eso una excepción al convertir la foto salía por la zona de errores de
/// Flutter y dejaba la rueda girando para siempre.
void main() {
  const GalleryItem photo = GalleryItem(
    id: 'foto-1',
    type: StoryMediaType.image,
  );

  test('una foto que se puede abrir sale lista para publicar', () async {
    final _FakeGallery gallery = _FakeGallery(ready: XFile('/tmp/IMG.jpg'));

    final StoryPickResult result = await pickStoryMedia(gallery, photo);

    expect(result.isReady, isTrue);
    expect(result.file!.path, '/tmp/IMG.jpg');
    expect(result.message, isNull);
  });

  test('un video largo se rechaza SIN bajar el fichero', () async {
    // Bajarlo de iCloud para luego rechazarlo sería hacerle esperar para nada.
    final _FakeGallery gallery = _FakeGallery(ready: XFile('/tmp/v.mp4'));

    final StoryPickResult result = await pickStoryMedia(
      gallery,
      GalleryItem(
        id: 'video-1',
        type: StoryMediaType.video,
        videoDuration: kStoryMaxVideoDuration + const Duration(seconds: 5),
      ),
    );

    expect(result.isReady, isFalse);
    expect(result.message, contains('segundos'));
    expect(
      gallery.fileCalls,
      0,
      reason: 'no se descarga algo que ya sabemos que vamos a rechazar',
    );
  });

  test('un fichero que no llega dice que puede estar bajandose', () async {
    final _FakeGallery gallery = _FakeGallery(ready: null);

    final StoryPickResult result = await pickStoryMedia(gallery, photo);

    expect(result.isReady, isFalse);
    expect(
      result.message,
      storyRejectionMessage(StoryMediaRejection.unavailable),
    );
  });

  test('si convertir falla se enseña el motivo, no el volcado', () async {
    final _FakeGallery gallery = _FakeGallery(
      error: const StoryImageConversionException(
        'Esta foto está en HEIC y no hemos podido convertirla.',
      ),
    );

    final StoryPickResult result = await pickStoryMedia(gallery, photo);

    expect(result.isReady, isFalse);
    expect(result.message, 'Esta foto está en HEIC y no hemos podido convertirla.');
    expect(result.message, isNot(contains('Exception')));
  });

  test('un fallo cualquiera tampoco deja a la persona sin nada', () async {
    // Antes, cualquier excepción aquí no la cogía nadie: rueda girando para
    // siempre y ni un mensaje.
    final _FakeGallery gallery = _FakeGallery(
      error: StateError('canal nativo caido'),
    );

    final StoryPickResult result = await pickStoryMedia(gallery, photo);

    expect(result.isReady, isFalse);
    expect(result.message, isNotEmpty);
    expect(result.message, isNot(contains('canal nativo caido')));
  });

  test('el canal nativo lanzando no acaba hablando de publicar', () async {
    // Es lo que hace `photo_manager` de verdad con una foto de iCloud que no
    // baja: `replyError` en nativo y PlatformException en Dart. Aquí todavía no
    // se ha publicado nada, así que hablar de publicar y de la conexión manda a
    // mirar donde no es.
    final _FakeGallery gallery = _FakeGallery(
      error: PlatformException(
        code: 'Asset foto-1 file cannot be obtained.',
      ),
    );

    final StoryPickResult result = await pickStoryMedia(gallery, photo);

    expect(result.isReady, isFalse);
    expect(result.message, isNot(contains('publicar')));
    expect(result.message, isNot(contains('cannot be obtained')));
  });
}

class _FakeGallery implements StoryGallery {
  _FakeGallery({this.ready, this.error});

  final XFile? ready;
  final Object? error;
  int fileCalls = 0;

  @override
  Future<XFile?> file(String id) async {
    fileCalls++;
    if (error != null) throw error!;
    return ready;
  }

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<List<GalleryItem>> load({required int page, int pageSize = 60}) async =>
      const <GalleryItem>[];

  @override
  Future<Uint8List?> thumbnail(String id, {int size = 240}) async => null;
}
