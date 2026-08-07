import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/domain/story_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reglas del compositor que sustituyó al editor.
///
/// Sin editor ya no hay recorte, así que la validación es lo único que impide
/// publicar algo que el backend va a rechazar DESPUÉS de subir el fichero
/// entero: en móvil eso son megas y minutos tirados.
void main() {
  group('Qué se puede publicar', () {
    test('una foto siempre pasa', () {
      expect(checkStoryMedia(type: StoryMediaType.image), isNull);
    });

    test('un vídeo dentro del tope pasa', () {
      expect(
        checkStoryMedia(
          type: StoryMediaType.video,
          videoDuration: kStoryMaxVideoDuration,
        ),
        isNull,
        reason: 'el límite es inclusivo: 15 s exactos valen',
      );
    });

    test('un vídeo más largo se rechaza en vez de cortarse solo', () {
      expect(
        checkStoryMedia(
          type: StoryMediaType.video,
          videoDuration: kStoryMaxVideoDuration + const Duration(seconds: 1),
        ),
        StoryMediaRejection.videoTooLong,
      );
    });

    test('un vídeo sin duración conocida NO se bloquea', () {
      // Metadatos ilegibles no son motivo para impedir publicar: el backend
      // tiene su propio límite y bloquear aquí castigaría a quien no ha hecho
      // nada mal.
      expect(
        checkStoryMedia(type: StoryMediaType.video, videoDuration: null),
        isNull,
      );
    });

    test('un fichero que ya no existe se rechaza con su propio motivo', () {
      // Pasa de verdad: un asset de iCloud que no llega a descargarse, o una
      // foto borrada entre que se pinta la cuadrícula y se toca.
      expect(
        checkStoryMedia(type: StoryMediaType.image, fileExists: false),
        StoryMediaRejection.unavailable,
      );
    });
  });

  group('Duración con la que se publica', () {
    test('una foto dura lo que dura una foto', () {
      expect(
        storyDurationSeconds(type: StoryMediaType.image),
        kStoryPhotoSeconds,
      );
    });

    test('un vídeo dura lo suyo', () {
      expect(
        storyDurationSeconds(
          type: StoryMediaType.video,
          videoDuration: const Duration(seconds: 8),
        ),
        8,
      );
    });

    test('un vídeo de 0 s no deja la historia en blanco', () {
      // Con duración 0 el visor pasaría de largo sin enseñar nada y parecería
      // que la publicación falló.
      expect(
        storyDurationSeconds(
          type: StoryMediaType.video,
          videoDuration: Duration.zero,
        ),
        greaterThanOrEqualTo(1),
      );
    });

    test('nunca se pasa del tope aunque el fichero mienta', () {
      expect(
        storyDurationSeconds(
          type: StoryMediaType.video,
          videoDuration: const Duration(minutes: 5),
        ),
        kStoryMaxVideoDuration.inSeconds,
      );
    });
  });

  group('Los motivos se explican', () {
    test('cada rechazo dice qué hacer', () {
      for (final StoryMediaRejection r in StoryMediaRejection.values) {
        final String message = storyRejectionMessage(r);
        expect(message, isNotEmpty);
        expect(
          message.length,
          greaterThan(30),
          reason: 'sin editor, la persona solo puede arreglarlo fuera de la '
              'app: el mensaje tiene que decirle cómo',
        );
      }
    });
  });
}
