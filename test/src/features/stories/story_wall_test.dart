import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/stories/data/story_repository.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/domain/story_wall.dart';
import 'package:flutter_test/flutter_test.dart';

/// Discover deja de ser un feed de perfiles y pasa a ser un muro de HISTORIAS.
///
/// La regla que fija este test: el ORDEN lo pone el pipeline del feed (filtros,
/// ranking orgánico, Boost pagado, modo viaje, Slow Dating, IA, "te dio like"),
/// y las historias solo deciden QUIÉN se pinta. Si el muro reordenara por
/// historia, se perdería todo eso —incluido el Boost que alguien ha pagado— y
/// el usuario vería gente que sus filtros excluyen.
///
/// Se ejercita [buildStoryWall], que es lo que corre en producción. Antes este
/// fichero reimplementaba la regla a mano, así que los 6 tests seguían en verde
/// con el índice recolocándose a 0 y reponiendo a quien ya se había swipeado.
SeedProfile _profile(String id) => SeedProfile.fromMap(id, <String, dynamic>{
      'displayName': 'Perfil $id',
      'gender': 'female',
      'interestedIn': <String>['male'],
      'country': 'España',
    });

Story _story(
  String owner, {
  required String id,
  String visibility = 'discovery',
  Duration expiresIn = const Duration(hours: 12),
}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': owner,
      'displayName': 'Perfil $owner',
      'mediaType': 'image',
      'imageUrl': 'https://example.test/$id.jpg',
      'status': 'active',
      'visibility': visibility,
      'expiresAt': DateTime.now().add(expiresIn).toIso8601String(),
    });

void main() {
  group('El muro solo muestra a quien tiene historias vivas', () {
    test('quien no tiene historias no ocupa sitio', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b'), _profile('c')],
        storiesByOwner: <String, List<Story>>{
          'b': <Story>[_story('b', id: 's1')],
        },
      );
      expect(wall.profiles.map((SeedProfile p) => p.id), <String>['b']);
    });

    test('sin historias, el muro queda vacío (no cae al feed de perfiles)', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: const <String, List<Story>>{},
      );
      expect(wall.profiles, isEmpty);
      expect(wall.isExhausted, isTrue);
    });

    test('una historia vencida no mete a su dueño en el muro', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('z')],
        storiesByOwner: <String, List<Story>>{
          'z': <Story>[
            _story('z', id: 'vieja', expiresIn: const Duration(hours: -1)),
          ],
        },
      );
      expect(wall.profiles, isEmpty,
          reason: 'el limpiador corre cada hora: puede haber caducadas activas');
    });
  });

  group('El orden lo manda el pipeline, no las historias', () {
    test('se respeta el orden del pool aunque haya más historias abajo', () {
      // 'c' está el último en el pool (peor encaje / sin Boost) pero es quien
      // más historias tiene: aun así NO adelanta a 'a'.
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b'), _profile('c')],
        storiesByOwner: <String, List<Story>>{
          'a': <Story>[_story('a', id: 'a1')],
          'c': <Story>[
            _story('c', id: 'c1'),
            _story('c', id: 'c2'),
            _story('c', id: 'c3'),
          ],
        },
      );
      expect(wall.profiles.map((SeedProfile p) => p.id), <String>['a', 'c']);
    });
  });

  group('Con el flag storiesEnabled apagado, Discover sigue siendo usable', () {
    // `storiesEnabled` es false por defecto. Si el muro se aplicara igualmente,
    // todo el mundo vería Discover vacío hasta que alguien encendiera el flag:
    // el rediseño no puede dejar la app sin pantalla de descubrimiento porque
    // una bandera remota esté apagada.
    test('sin muro activo se cae al feed de perfiles completo', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: const <String, List<Story>>{},
        wallActive: false,
      );
      expect(wall.profiles.map((SeedProfile p) => p.id), <String>['a', 'b']);
    });

    test('sin muro activo NO se filtra por historias', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: <String, List<Story>>{
          'b': <Story>[_story('b', id: 's1')],
        },
        wallActive: false,
      );
      expect(wall.profiles.map((SeedProfile p) => p.id), <String>['a', 'b'],
          reason: 'con el flag apagado el feed de perfiles va intacto');
    });
  });

  group('El índice no repone a quien ya se ha decidido', () {
    final Map<String, List<Story>> tres = <String, List<Story>>{
      'a': <Story>[_story('a', id: 'a1')],
      'b': <Story>[_story('b', id: 'b1')],
      'c': <Story>[_story('c', id: 'c1')],
    };
    final List<SeedProfile> pool = <SeedProfile>[
      _profile('a'),
      _profile('b'),
      _profile('c'),
    ];

    test('la persona que se está viendo no se mueve de sitio', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: pool,
        storiesByOwner: tres,
        consumedUids: <String>{'a'},
        currentUid: 'b',
      );
      expect(wall.index, 1);
      expect(wall.profiles[wall.index].id, 'b');
    });

    test('si le caduca la historia a quien se veía, NO se vuelve al principio',
        () {
      // El stream de historias es global: emite ante cualquier cambio de
      // cualquier historia (hasta el viewsCount que escribe ver una ajena).
      final StoryWall wall = buildStoryWall(
        rankedPool: pool,
        storiesByOwner: <String, List<Story>>{
          'a': tres['a']!,
          'c': tres['c']!,
        },
        consumedUids: <String>{'a'},
        currentUid: 'b',
      );
      expect(wall.profiles[wall.index].id, 'c',
          reason: 'a ya se pasó: reponerlo generaba otro pase y otro nopeSent');
    });

    test('el muro agotado SIGUE agotado tras recalcular', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: pool,
        storiesByOwner: tres,
        consumedUids: <String>{'a', 'b', 'c'},
        // Sin persona actual: el feed estaba en el estado "se acabó".
      );
      expect(wall.isExhausted, isTrue);
      expect(wall.index, wall.profiles.length);
    });

    test('quien publica mientras tanto sí entra, aunque el muro estuviera al fin',
        () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[...pool, _profile('d')],
        storiesByOwner: <String, List<Story>>{
          ...tres,
          'd': <Story>[_story('d', id: 'd1')],
        },
        consumedUids: <String>{'a', 'b', 'c'},
      );
      expect(wall.isExhausted, isFalse);
      expect(wall.profiles[wall.index].id, 'd');
    });
  });

  group('Bloquear saca del muro (Guideline 1.2)', () {
    test('el bloqueado no vuelve al recomponerse el muro', () {
      final StoryWall wall = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('a'), _profile('b')],
        storiesByOwner: <String, List<Story>>{
          'a': <Story>[_story('a', id: 'a1')],
          'b': <Story>[_story('b', id: 'b1')],
        },
        excludedUids: <String>{'b'},
        currentUid: 'b',
      );
      expect(wall.profiles.map((SeedProfile p) => p.id), <String>['a']);
      expect(wall.profiles[wall.index].id, 'a');
    });
  });

  group('"Solo matches" no es contenido de descubrimiento', () {
    // Las reglas dejan leer /stories a cualquier usuario autenticado, así que
    // este filtro de cliente es el único que protege esa elección del usuario.
    test('una historia de solo matches no alimenta el muro', () {
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupWallStories(<Story>[
        _story('a', id: 'a1', visibility: 'matches'),
        _story('b', id: 'b1'),
      ]);
      expect(byOwner.keys, <String>['b']);
    });

    test('se descarta la propia y la de los bloqueados', () {
      final Map<String, List<Story>> byOwner = StoryRepository.groupWallStories(
        <Story>[
          _story('yo', id: 'y1'),
          _story('bloqueado', id: 'x1'),
          _story('ok', id: 'o1'),
        ],
        excludeUid: 'yo',
        excludedOwners: <String>{'bloqueado'},
      );
      expect(byOwner.keys, <String>['ok']);
    });

    test('las de una persona salen de más antigua a más reciente', () {
      final Story vieja = Story.fromMap('v', <String, dynamic>{
        'ownerUid': 'a',
        'mediaType': 'image',
        'imageUrl': 'https://example.test/v.jpg',
        'status': 'active',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'expiresAt': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      });
      final Story nueva = Story.fromMap('n', <String, dynamic>{
        'ownerUid': 'a',
        'mediaType': 'image',
        'imageUrl': 'https://example.test/n.jpg',
        'status': 'active',
        'createdAt': DateTime(2026, 2, 1).toIso8601String(),
        'expiresAt': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      });
      final Map<String, List<Story>> byOwner =
          StoryRepository.groupWallStories(<Story>[nueva, vieja]);
      expect(byOwner['a']!.map((Story s) => s.storyId), <String>['v', 'n']);
    });
  });

  group('Por que activateBoost exige tener historia', () {
    test('el primero del pool (posicion de impulsado) cae si no tiene historia',
        () {
      // El Boost solo cambia el ORDEN del pool: pone al impulsado el primero.
      // Pero el muro filtra DESPUES por historia viva, asi que un impulsado sin
      // historia desaparece de Discover igual que cualquiera.
      //
      // Un Boost se consume POR TIEMPO, no por impresiones entregadas: activarlo
      // en ese estado quemaba el reloj entero sin enseñar el perfil ni una vez.
      // Dinero cobrado a cambio de nada. Por eso `activateBoost`
      // (functions/src/boosts.ts) se niega a cobrar con `needs_story` cuando el
      // muro esta encendido y no hay historia viva.
      //
      // Si algun dia este test se pone en rojo porque el muro SI conserva al
      // impulsado, hay que quitar aquella puerta: estaria cobrando de menos.
      final StoryWall muro = buildStoryWall(
        rankedPool: <SeedProfile>[_profile('impulsado'), _profile('b')],
        storiesByOwner: <String, List<Story>>{
          'b': <Story>[_story('b', id: 's1')],
        },
      );
      expect(
        muro.profiles.map((SeedProfile p) => p.id),
        <String>['b'],
        reason: 'el impulsado sin historia no llega a verse',
      );
    });
  });
}
