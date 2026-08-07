import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El muro de Discover solo enseña a quien tiene una historia viva, así que
/// PUBLICAR es lo que mantiene la pantalla con contenido.
///
/// Esto ya se rompió una vez: al quitar la tira de aros (`StoriesBar`) del feed
/// se fue con ella el único sitio desde el que se abría `CreateStoryScreen`.
/// Nadie podía publicar, las historias caducan a las 72 h y Discover se habría
/// quedado en "Nadie está contando nada ahora mismo" para siempre. El editor
/// seguía compilando y ningún test se enteró.
void main() {
  test('se puede llegar a CreateStoryScreen desde alguna pantalla', () {
    final List<String> users = _filesInstantiating('CreateStoryScreen')
        .where((String path) => !path.endsWith('create_story_screen.dart'))
        .toList(growable: false);
    expect(
      users,
      isNotEmpty,
      reason: 'Nadie abre CreateStoryScreen: no hay forma de publicar una '
          'historia y el muro de Discover se vacía solo en 72 h.',
    );
  });

  test('el feed ofrece el punto de entrada para contar algo', () {
    final String feed = File(
      'lib/src/features/feed/presentation/feed_screen.dart',
    ).readAsStringSync();
    expect(
      feed.contains('MyStoryButton('),
      isTrue,
      reason: 'La cabecera del muro tiene que ofrecer publicar: es la única '
          'entrada que queda tras retirar la tira de historias.',
    );
  });

  test('MyStoryButton abre el editor y respeta el tope del servidor', () {
    final String button = File(
      'lib/src/features/stories/presentation/my_story_button.dart',
    ).readAsStringSync();
    expect(button.contains('CreateStoryScreen('), isTrue);
    expect(
      button.contains('StoryService.maxActiveStories'),
      isTrue,
      reason: 'Sin el tope, la UI ofrece subir una sexta historia que el '
          'servidor rechaza después de procesar y subir el vídeo.',
    );
  });
}

/// Ficheros de `lib/` que construyen la clase [className].
List<String> _filesInstantiating(String className) {
  final List<String> hits = <String>[];
  for (final FileSystemEntity entity
      in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.readAsStringSync().contains('$className(')) {
      hits.add(entity.path.replaceAll(r'\', '/'));
    }
  }
  return hits;
}
