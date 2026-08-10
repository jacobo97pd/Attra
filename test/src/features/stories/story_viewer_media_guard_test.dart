import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un medio roto no puede quedarse con el relato entero de una persona.
///
/// El fallo real: el dueño subió tres historias (un vídeo y dos fotos) y solo
/// veía la primera. Los dos visores pintaban el aviso de "no se pudo
/// reproducir" y SALÍAN: ni temporizador ni listener, así que nada volvía a
/// llamar a `_next()`. El vídeo es el único medio sin reloj propio —la imagen
/// tiene su `Timer.periodic`— y dependía en exclusiva de que el reproductor
/// avisara del final, aviso que no llega si no inicializa o si el MP4 viene sin
/// duración fiable.
///
/// `BlindStoryViewerScreen` se monta y se recorre de verdad en
/// blind_story_viewer_test.dart. `StoryViewerScreen` —el visor de MIS historias,
/// el único sitio donde el dueño ve las suyas— NO se puede montar en un test:
/// exige un `StoryService`, que exige Firestore, Functions y Storage reales, y
/// no hay mocks de Firebase en el proyecto (mismo motivo y mismo enfoque que
/// story_composer_wiring_test.dart). Así que sobre él se fijan las invariantes
/// en el código, que es la única red que queda.
const String _blind =
    'lib/src/features/stories/presentation/blind_story_viewer_screen.dart';
const String _mine =
    'lib/src/features/stories/presentation/story_viewer_screen.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  for (final String path in <String>[_blind, _mine]) {
    final String source = _read(path);
    final String name = path.split('/').last;

    group(name, () {
      test('el aviso de medio roto se pone SIEMPRE por _failMedia', () {
        // Un `_mediaError = 'algo'` suelto es exactamente el callejón sin
        // salida: pinta el aviso y no programa el avance.
        expect(
          RegExp("_mediaError\\s*=\\s*'").hasMatch(source),
          isFalse,
          reason: 'poner el aviso a mano se salta el reloj que hace seguir con '
              'las demás historias',
        );
        expect(source.contains('void _failMedia('), isTrue);
      });

      test('_failMedia programa el avance', () {
        final int inicio = source.indexOf('void _failMedia(');
        final String cuerpo = source.substring(inicio, inicio + 400);
        expect(cuerpo.contains('Timer('), isTrue);
        expect(
          cuerpo.contains('_next()'),
          isTrue,
          reason: 'sin esto la historia rota se queda para siempre y las otras '
              'dos solo se alcanzan tocando a ciegas el lado derecho',
        );
      });

      test('el vídeo tiene reloj de seguridad', () {
        expect(
          source.contains('_armVideoWatchdog('),
          isTrue,
          reason: 'el vídeo es el único medio sin reloj propio: si el '
              'reproductor no avisa del final, nadie avanza',
        );
      });

      test('una carga que llega tarde no pisa la historia nueva', () {
        // Se toca a la derecha mientras el vídeo inicializa: `_load` desecha ese
        // controlador y arranca la foto siguiente. Cuando la promesa vuelve, sin
        // esta comprobación escribía "No se pudo reproducir el vídeo" ENCIMA de
        // la foto, o se ponía a sonar por debajo de ella.
        expect(
          RegExp(r'identical\(_(controller|video), \w+\)').hasMatch(source),
          isTrue,
        );
      });

      test('los temporizadores se cancelan al cerrar', () {
        final int inicio = source.indexOf('void dispose()');
        final String cuerpo = source.substring(inicio, inicio + 320);
        expect(cuerpo.contains('_mediaWatchdog?.cancel()'), isTrue);
      });
    });
  }
}
