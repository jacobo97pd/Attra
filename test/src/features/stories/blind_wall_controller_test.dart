import 'package:attra/src/features/feed/domain/rewind_policy.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/presentation/blind_wall_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// El visor a ciegas NO puede tener su propia ruta al backend.
///
/// Antes el visor de stories llamaba a `storyService.replyToStory`: la misma
/// acción (like/Attra) se contaba distinto según la hicieras desde la tarjeta o
/// desde el visor, y el gate de likes, el rewind, las métricas y los anuncios se
/// quedaban fuera. Este test fija que todo pasa por los callbacks del feed.
Story _story(String owner, String id) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': owner,
      'mediaType': 'image',
      'imageUrl': 'https://example.test/$id.jpg',
      'status': 'active',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

/// Marcha atrás disponible (Plus con un gesto guardado). La mayoría de los
/// tests de sincronización no la miran, pero `sync` la exige a propósito: el
/// visor pinta el botón con ella y un valor por defecto era justo la forma de
/// que el feed se olvidara de volcarla.
final RewindState _libre = const RewindState(tier: RewindTier.plus).record(
  const RewindEntry(targetUid: 'z', kind: FeedActionKind.like),
);

BlindWallPerson _person(String uid, {int stories = 1, int? age = 28}) =>
    BlindWallPerson(
      uid: uid,
      displayName: 'Perfil $uid',
      age: age,
      stories: <Story>[
        for (int i = 0; i < stories; i++) _story(uid, '$uid$i'),
      ],
    );

void main() {
  late List<String> calls;
  late BlindWallController controller;

  setUp(() {
    calls = <String>[];
    controller = BlindWallController(
      beforeLike: () async {
        calls.add('beforeLike');
        return true;
      },
      onLike: () async => calls.add('like'),
      onPass: () async => calls.add('pass'),
      onSuperAttra: () async => calls.add('attra'),
      onSkip: () => calls.add('skip'),
      onStoriesSeen: (List<Story> s) => calls.add('seen:${s.length}'),
      onRewind: () async => calls.add('rewind'),
      onSafety: () => calls.add('safety'),
    );
  });

  tearDown(() => controller.dispose());

  group('Todas las acciones vuelven al feed', () {
    test('like, pase y Super Attra van por sus callbacks', () async {
      expect(await controller.beforeLike(), isTrue);
      await controller.onLike();
      await controller.onPass();
      await controller.onSuperAttra();
      controller.onSkip();
      controller.onSafety!();
      // La marcha atrás también: el visor no puede llamar a `rewindFeedAction`
      // por su cuenta ni llevar su propio historial (el gate de plan, el
      // `_excluded` y el `_consumed` que hay que limpiar viven en el feed).
      await controller.onRewind();
      expect(calls, <String>[
        'beforeLike',
        'like',
        'pass',
        'attra',
        'skip',
        'safety',
        'rewind',
      ]);
    });
  });

  group('Solo nombre y edad', () {
    // Conocer a la persona es la recompensa del match: si aquí acabaran
    // apareciendo estudios, trabajo o bio, Discover deja de ser "a ciegas".
    test('la etiqueta del visor es nombre y edad', () {
      expect(_person('a').label, 'Perfil a, 28');
    });

    test('sin edad pública se enseña solo el nombre', () {
      expect(_person('a', age: null).label, 'Perfil a');
      expect(_person('a', age: 0).label, 'Perfil a');
    });
  });

  group('Sincronización con el feed', () {
    test('cambiar de persona avisa al visor', () {
      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      expect(notifications, 1);
      expect(controller.current?.uid, 'a');

      controller.sync(person: _person('b'), shouldClose: false, rewind: _libre);
      expect(notifications, 2);
      expect(controller.current?.uid, 'b');
    });

    test('volcar lo mismo NO avisa (se llama en cada frame del feed)', () {
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      expect(notifications, 0,
          reason: 'si notificara siempre, el vídeo se recargaría en bucle');
    });

    test('publicar una historia nueva de la misma persona sí avisa', () {
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.sync(
          person: _person('a', stories: 3),
          shouldClose: false,
          rewind: _libre);
      expect(notifications, 1);
      expect(controller.current?.stories.length, 3);
    });

    test('sin nadie a quien enseñar, el visor se cierra', () {
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      controller.sync(person: null, shouldClose: true, rewind: _libre);
      expect(controller.shouldClose, isTrue);
    });

    test('el anuncio intercalado cierra el visor y luego lo libera', () {
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      // Toca anuncio: el visor se cierra y el feed pinta la ad card.
      controller.sync(person: _person('b'), shouldClose: true, rewind: _libre);
      expect(controller.shouldClose, isTrue);
      // Cerrado el anuncio, el muro vuelve a estar disponible.
      controller.sync(person: _person('b'), shouldClose: false, rewind: _libre);
      expect(controller.shouldClose, isFalse);
      expect(controller.current?.uid, 'b');
    });
  });

  group('La marcha atrás llega al visor', () {
    test('gastar el último gesto apaga el botón sin cambiar de persona', () {
      // Es el caso real: Plus deshace, sigue en la misma persona y el botón
      // tiene que pasar a "no queda nada". Si la firma de `sync` solo mirara a
      // la persona, el visor se quedaría enseñándolo disponible para siempre.
      final RewindState plus = const RewindState(tier: RewindTier.plus).record(
        const RewindEntry(targetUid: 'z', kind: FeedActionKind.pass),
      );
      controller.sync(
          person: _person('a'), shouldClose: false, rewind: plus);
      expect(controller.rewind.status, RewindStatus.ready);

      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.sync(
          person: _person('a'), shouldClose: false, rewind: plus.undo());

      expect(notifications, 1);
      expect(controller.rewind.status, RewindStatus.empty);
      expect(controller.rewind.remaining, 0);
    });

    test('volcar la MISMA marcha atrás sigue sin avisar', () {
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.sync(person: _person('a'), shouldClose: false, rewind: _libre);
      expect(notifications, 0);
    });
  });
}
