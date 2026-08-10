import 'package:attra/src/features/stories/data/story_repository.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tocar el aro de un match en Chats tiene que abrir TODAS sus historias.
///
/// Antes no: la ruta de Chats usaba `observeLiveStories`, que colapsaba cada
/// grupo a UNA sola story (la más reciente). Es herencia de cuando solo se
/// admitía una por persona; con el máximo actual de 5, las demás quedaban
/// literalmente inalcanzables desde ahí — el visor pintaba una sola barra y el
/// primer toque a la derecha cerraba la pantalla.
Story _story(
  String id, {
  required String owner,
  required int minute,
  String visibility = 'discovery',
  bool expired = false,
}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': owner,
      'mediaType': 'image',
      'imageUrl': 'https://example.test/$id.jpg',
      'status': 'active',
      'visibility': visibility,
      'createdAt': DateTime.utc(2026, 8, 10, 8, minute).toIso8601String(),
      'expiresAt': expired
          ? DateTime.now().subtract(const Duration(hours: 1)).toIso8601String()
          : DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

void main() {
  group('El grupo NO se colapsa', () {
    test('tres historias de la misma persona salen las tres', () {
      // El caso real: un vídeo y dos fotos publicados con segundos de
      // diferencia, de los que solo se veía el primero.
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(<Story>[
        _story('a', owner: 'jacobo', minute: 43),
        _story('b', owner: 'jacobo', minute: 44),
        _story('c', owner: 'jacobo', minute: 45),
      ]);

      expect(byOwner['jacobo'], hasLength(3));
    });

    test('salen de más antigua a más reciente', () {
      // El visor abre por el índice 0, así que el orden decide cuál se ve
      // primero.
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(<Story>[
        _story('nueva', owner: 'x', minute: 50),
        _story('vieja', owner: 'x', minute: 10),
      ]);

      expect(byOwner['x']!.map((Story s) => s.storyId), <String>['vieja', 'nueva']);
    });

    test('cada persona tiene su propio grupo', () {
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(<Story>[
        _story('a', owner: 'uno', minute: 1),
        _story('b', owner: 'dos', minute: 2),
        _story('c', owner: 'uno', minute: 3),
      ]);

      expect(byOwner['uno'], hasLength(2));
      expect(byOwner['dos'], hasLength(1));
    });
  });

  group('Qué se descarta', () {
    test('las propias no salen: uno no se ve a sí mismo en Chats', () {
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(
        <Story>[_story('a', owner: 'yo', minute: 1)],
        excludeUid: 'yo',
      );

      expect(byOwner, isEmpty);
    });

    test('las de un bloqueado no salen', () {
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(
        <Story>[_story('a', owner: 'bloqueado', minute: 1)],
        excludedOwners: <String>{'bloqueado'},
      );

      expect(byOwner, isEmpty);
    });

    test('una caducada no cuenta aunque siga marcada activa', () {
      // El limpiador programado corre cada hora: entre medias hay documentos
      // `active` ya vencidos.
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(<Story>[
        _story('viva', owner: 'x', minute: 1),
        _story('vencida', owner: 'x', minute: 2, expired: true),
      ]);

      expect(byOwner['x']!.map((Story s) => s.storyId), <String>['viva']);
    });
  });

  group('Visibilidad: aquí SÍ entran las de "solo matches"', () {
    test('una historia de solo matches se ve por esta ruta', () {
      // Es la diferencia con `groupWallStories`, que las descarta porque
      // alimenta el muro de Discover y eso es descubrimiento. Aquí el
      // destinatario es justamente un match: filtrarlas dejaría esas historias
      // sin ningún sitio donde verse.
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupMatchStories(<Story>[
        _story('privada', owner: 'x', minute: 1, visibility: 'matches'),
      ]);

      expect(byOwner['x'], hasLength(1));
    });

    test('el muro, en cambio, sí las descarta', () {
      // Contraste explícito: si algún día alguien unifica las dos funciones,
      // este test dice por qué no se puede.
      final Map<String, List<Story>> muro = StoryRepository.groupWallStories(
        <Story>[_story('privada', owner: 'x', minute: 1, visibility: 'matches')],
      );

      expect(muro, isEmpty);
    });
  });
}
