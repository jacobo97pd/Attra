import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:flutter_test/flutter_test.dart';

/// Discover deja de ser un feed de perfiles y pasa a ser un muro de HISTORIAS.
///
/// La regla que fija este test: el ORDEN lo pone el pipeline del feed (filtros,
/// ranking orgánico, Boost pagado, modo viaje, Slow Dating, IA, "te dio like"),
/// y las historias solo deciden QUIÉN se pinta. Si el muro reordenara por
/// historia, se perdería todo eso —incluido el Boost que alguien ha pagado— y
/// el usuario vería gente que sus filtros excluyen.
SeedProfile _profile(String id) => SeedProfile.fromMap(id, <String, dynamic>{
      'displayName': 'Perfil $id',
      'gender': 'female',
      'interestedIn': <String>['male'],
      'country': 'España',
    });

Story _story(String owner, {required String id}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': owner,
      'displayName': 'Perfil $owner',
      'mediaType': 'image',
      'imageUrl': 'https://example.test/$id.jpg',
      'status': 'active',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

/// Réplica de `_FeedScreenState._applyStoryWall`.
///
/// [wallActive] es `_storyWallActive`: el flag remoto `storiesEnabled` (que hoy
/// viene APAGADO por defecto) más la existencia del servicio de historias.
List<SeedProfile> buildWall({
  required List<SeedProfile> rankedPool,
  required Map<String, List<Story>> storiesByOwner,
  bool wallActive = true,
}) {
  if (!wallActive) return rankedPool;
  return rankedPool
      .where((SeedProfile p) => (storiesByOwner[p.id]?.isNotEmpty ?? false))
      .toList(growable: false);
}

void main() {
  group('El muro solo muestra a quien tiene historias vivas', () {
    test('quien no tiene historias no ocupa sitio', () {
      final List<SeedProfile> pool = <SeedProfile>[
        _profile('a'),
        _profile('b'),
        _profile('c'),
      ];
      final List<SeedProfile> wall = buildWall(
        rankedPool: pool,
        storiesByOwner: <String, List<Story>>{
          'b': <Story>[_story('b', id: 's1')],
        },
      );
      expect(wall.map((SeedProfile p) => p.id), <String>['b']);
    });

    test('sin historias, el muro queda vacío (no cae al feed de perfiles)', () {
      final List<SeedProfile> wall = buildWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: const <String, List<Story>>{},
      );
      expect(wall, isEmpty);
    });
  });

  group('El orden lo manda el pipeline, no las historias', () {
    test('se respeta el orden del pool aunque haya más historias abajo', () {
      // 'c' está el último en el pool (peor encaje / sin Boost) pero es quien
      // más historias tiene: aun así NO adelanta a 'a'.
      final List<SeedProfile> pool = <SeedProfile>[
        _profile('a'),
        _profile('b'),
        _profile('c'),
      ];
      final List<SeedProfile> wall = buildWall(
        rankedPool: pool,
        storiesByOwner: <String, List<Story>>{
          'a': <Story>[_story('a', id: 'a1')],
          'c': <Story>[
            _story('c', id: 'c1'),
            _story('c', id: 'c2'),
            _story('c', id: 'c3'),
          ],
        },
      );
      expect(wall.map((SeedProfile p) => p.id), <String>['a', 'c']);
    });
  });

  group('Con el flag storiesEnabled apagado, Discover sigue siendo usable', () {
    // `storiesEnabled` es false por defecto. Si el muro se aplicara igualmente,
    // todo el mundo vería Discover vacío hasta que alguien encendiera el flag:
    // el rediseño no puede dejar la app sin pantalla de descubrimiento porque
    // una bandera remota esté apagada.
    test('sin muro activo se cae al feed de perfiles completo', () {
      final List<SeedProfile> pool = <SeedProfile>[
        _profile('a'),
        _profile('b'),
      ];
      final List<SeedProfile> wall = buildWall(
        rankedPool: pool,
        storiesByOwner: const <String, List<Story>>{},
        wallActive: false,
      );
      expect(wall.map((SeedProfile p) => p.id), <String>['a', 'b']);
    });

    test('sin muro activo NO se filtra por historias', () {
      final List<SeedProfile> wall = buildWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: <String, List<Story>>{
          'b': <Story>[_story('b', id: 's1')],
        },
        wallActive: false,
      );
      expect(wall.map((SeedProfile p) => p.id), <String>['a', 'b'],
          reason: 'con el flag apagado el feed de perfiles va intacto');
    });
  });

  group('Historias caducadas', () {
    test('una historia vencida no mete a su dueño en el muro', () {
      final Story vencida = Story.fromMap('vieja', <String, dynamic>{
        'ownerUid': 'z',
        'mediaType': 'image',
        'imageUrl': 'https://example.test/z.jpg',
        'status': 'active',
        'expiresAt':
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      });
      expect(vencida.isLive, isFalse,
          reason: 'el muro se apoya en isLive para no pintar caducadas');
    });
  });
}
