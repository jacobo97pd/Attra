import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:attra/src/features/stories/domain/story_errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Que el fallo deje de ser mudo.
///
/// Lo que se veía: `StoryServiceException(null): No se pudo procesar la imagen`.
/// Es el `toString()` de la excepción, con nombre de clase y un código nulo: no
/// dice qué pasa ni qué se puede hacer.
void main() {
  test('un error con texto propio se enseña tal cual', () {
    const StoryUserMessageException error = StoryUserMessageException(
      'No hemos podido leer esta foto. Prueba con otra.',
    );

    expect(
      storyPublishFailureMessage(error),
      'No hemos podido leer esta foto. Prueba con otra.',
    );
  });

  test('el volcado tecnico de Storage NO se enseña', () {
    // Marcar toda StoryServiceException como presentable garantizaba que
    // "Error al subir: storage/retry-limit-exceeded - Max retry time exceeded"
    // acabara en un SnackBar: un código de Firebase y una frase en inglés.
    const StoryServiceException error = StoryServiceException(
      'Error al subir: storage/retry-limit-exceeded - Max retry time exceeded',
      code: 'storage/retry-limit-exceeded',
    );

    final String shown = storyPublishFailureMessage(error);
    expect(shown, isNot(contains('storage/retry-limit-exceeded')));
    expect(shown, isNot(contains('Max retry time exceeded')));
    expect(shown, isNot(contains('StoryServiceException')));
  });

  test('el detalle tecnico de un error presentable se queda en los logs', () {
    const StoryUserMessageException error = StoryUserMessageException(
      'No hemos podido preparar ese vídeo. Vuelve a intentarlo.',
      detail: 'PlatformException(io_failed, ...)',
    );

    expect(storyPublishFailureMessage(error), isNot(contains('io_failed')));
    expect(error.toString(), contains('io_failed'));
  });

  test('un error ajeno cae en algo generico pero accionable', () {
    // Un fallo de red o una excepción de Firebase no tienen por qué acabar en
    // pantalla con su nombre de clase.
    final String shown = storyPublishFailureMessage(
      StateError('Bad state: no host'),
    );

    expect(shown, isNot(contains('StateError')));
    expect(shown, isNot(contains('Bad state')));
    expect(shown.length, greaterThan(30));
  });

  test('un mensaje vacio no deja la pantalla muda', () {
    // Un backend que responde con código y sin texto no puede acabar enseñando
    // un aviso en blanco.
    expect(
      storyPublishFailureMessage(const StoryUserMessageException('')),
      isNotEmpty,
    );
    expect(
      storyPublishFailureMessage(const StoryUserMessageException('   ')),
      isNotEmpty,
    );
  });

  test('elegir del carrete no habla de publicar ni de la conexion', () {
    // Todavía no se ha subido nada: mandar a mirar la conexión cuando lo que ha
    // fallado es abrir el fichero manda a mirar donde no es.
    final String shown = storyMediaFailureMessage(StateError('boom'));

    expect(shown, isNot(contains('publicar')));
    expect(shown, isNot(contains('conexión')));
    expect(shown, isNotEmpty);
  });

  test('el motivo escrito para la persona sí se enseña al elegir', () {
    const StoryUserMessageException error = StoryUserMessageException(
      'Esta foto está en HEIC y no hemos podido convertirla.',
    );

    expect(
      storyMediaFailureMessage(error),
      'Esta foto está en HEIC y no hemos podido convertirla.',
    );
  });
}
