import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/presentation/blind_story_viewer_screen.dart';
import 'package:attra/src/features/stories/presentation/blind_wall_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TRES historias publicadas tienen que poder verse las TRES.
///
/// El dueño del producto subió tres (un vídeo y dos fotos) y solo veía una: la
/// primera. El visor era un callejón sin salida en cuanto el primer medio no
/// arrancaba —se pintaba el aviso y NADA volvía a llamar a `_next()`, ni
/// temporizador ni listener—, así que las otras dos solo se alcanzaban si el
/// usuario adivinaba que hay que tocar la mitad derecha de la pantalla.
///
/// Aquí se monta el visor DE VERDAD (no una réplica de su lógica) y se recorre
/// con toques y con el reloj. Lo que no se puede probar sin dispositivo es el
/// vídeo: `video_player` habla por canal nativo y en un test no hay plugin, así
/// que los casos de vídeo se cubren por su rama de "medio que no se puede
/// reproducir", que es exactamente la que se quedaba clavada.
Story _photo(String id, {int seconds = 1}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': 'a',
      'displayName': 'Fer',
      'mediaType': 'image',
      'imageUrl': 'https://example.test/$id.jpg',
      'durationSeconds': seconds,
      'status': 'active',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

/// Historia con el medio ROTO: el documento existe y está viva, pero no hay URL
/// que reproducir (es el equivalente testeable a un vídeo que no inicializa).
Story _brokenMedia(String id) => Story.fromMap(id, <String, dynamic>{
      'ownerUid': 'a',
      'displayName': 'Fer',
      'mediaType': 'image',
      'imageUrl': '',
      'status': 'active',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

/// Zona derecha de la pantalla de test (800x600): avanzar.
const Offset _derecha = Offset(700, 300);

void main() {
  late List<String> vistas;
  late List<String> acciones;
  late BlindWallController controller;
  late Future<bool> Function() gate;

  setUp(() {
    vistas = <String>[];
    acciones = <String>[];
    gate = () async => true;
    controller = BlindWallController(
      beforeLike: () => gate(),
      onLike: () async => acciones.add('like'),
      onPass: () async => acciones.add('pass'),
      onSuperAttra: () async => acciones.add('attra'),
      onSkip: () => acciones.add('skip'),
      onStoriesSeen: (List<Story> s) =>
          vistas.addAll(s.map((Story x) => x.storyId)),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> abrir(WidgetTester tester, List<Story> stories) async {
    controller.sync(
      person: BlindWallPerson(
        uid: 'a',
        displayName: 'Fer',
        age: 33,
        stories: stories,
      ),
      shouldClose: false,
    );
    await tester.pumpWidget(
      MaterialApp(home: BlindStoryViewerScreen(controller: controller)),
    );
    // La primera carga va post-frame (marcar "vista" hace setState en el feed y
    // eso revienta si se llama durante build).
    await tester.pump();
  }

  /// Desmonta para que los temporizadores del visor se cancelen: si quedara uno
  /// vivo, el propio framework de test lo marca como fuga.
  Future<void> cerrar(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// Deja pasar tiempo DE VERDAD y luego deja tiquear al temporizador del visor.
  ///
  /// El reloj de la historia de imagen se lleva con `DateTime.now()`, no con la
  /// duración que se le pasa a `pump`: adelantar el tiempo falso del test no
  /// mueve su progreso ni un milisegundo, así que hay que esperar de verdad.
  Future<void> pasarTiempo(WidgetTester tester, Duration d) async {
    await tester.runAsync(() => Future<void>.delayed(d));
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('tocando a la derecha se llega a las TRES', (
    WidgetTester tester,
  ) async {
    await abrir(tester, <Story>[_photo('s1'), _photo('s2'), _photo('s3')]);
    expect(vistas, <String>['s1']);

    await tester.tapAt(_derecha);
    await tester.pump();
    expect(vistas, <String>['s1', 's2']);

    await tester.tapAt(_derecha);
    await tester.pump();
    expect(vistas, <String>['s1', 's2', 's3']);

    // Pasada la última se salta a la SIGUIENTE PERSONA, sin like ni pase.
    await tester.tapAt(_derecha);
    await tester.pump();
    expect(acciones, <String>['skip']);

    await cerrar(tester);
  });

  testWidgets('sin tocar nada, el reloj también las pasa las tres', (
    WidgetTester tester,
  ) async {
    await abrir(tester, <Story>[
      _photo('s1'),
      _photo('s2'),
      _photo('s3'),
    ]);

    await pasarTiempo(tester, const Duration(milliseconds: 1100));
    expect(vistas, <String>['s1', 's2']);
    await pasarTiempo(tester, const Duration(milliseconds: 1100));
    expect(vistas, <String>['s1', 's2', 's3']);
    await pasarTiempo(tester, const Duration(milliseconds: 1100));
    expect(acciones, <String>['skip']);

    await cerrar(tester);
  });

  testWidgets('la barra pinta un segmento por historia', (
    WidgetTester tester,
  ) async {
    await abrir(tester, <Story>[_photo('s1'), _photo('s2'), _photo('s3')]);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    await cerrar(tester);
  });

  testWidgets('un medio que no se puede reproducir NO secuestra a las demás', (
    WidgetTester tester,
  ) async {
    // Es el caso del dueño: la primera de las tres era el vídeo. Si no arranca,
    // antes se pintaba el aviso y ahí se quedaba para siempre.
    await abrir(tester, <Story>[
      _brokenMedia('s1'),
      _photo('s2'),
      _photo('s3'),
    ]);
    expect(find.text('Esta historia no tiene imagen.'), findsOneWidget);
    expect(vistas, <String>['s1']);

    await tester.pump(const Duration(seconds: 4));
    expect(
      vistas,
      <String>['s1', 's2'],
      reason: 'una historia rota se enseña un momento y se sigue; si se queda, '
          'se come el relato entero de esa persona',
    );

    await cerrar(tester);
  });

  testWidgets('ni aunque estén rotas todas menos la última', (
    WidgetTester tester,
  ) async {
    await abrir(tester, <Story>[
      _brokenMedia('s1'),
      _brokenMedia('s2'),
      _photo('s3'),
    ]);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(vistas, <String>['s1', 's2', 's3']);
    await cerrar(tester);
  });

  testWidgets('mantener pulsado no salta de historia', (
    WidgetTester tester,
  ) async {
    // El reloj de seguridad se para con el dedo encima: si siguiera corriendo,
    // pararse a leer un texto acabaría pasando de historia solo.
    await abrir(tester, <Story>[
      _photo('s1', seconds: 2),
      _photo('s2', seconds: 2),
    ]);
    final TestGesture dedo = await tester.startGesture(_derecha);
    // Suficiente para que el gesto cuente como pulsación mantenida.
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await pasarTiempo(tester, const Duration(seconds: 3));
    expect(vistas, <String>['s1']);
    await dedo.up();
    await tester.pump();

    await cerrar(tester);
  });

  testWidgets('si el gate del like falla, el visor NO se queda bloqueado', (
    WidgetTester tester,
  ) async {
    // `_actionPending` se levanta ANTES de esperar el gate. Si el gate lanza
    // (registra analítica y abre un bottom sheet) nadie lo bajaba: `_locked`
    // quedaba puesto para siempre y `_next`/`_prev` pasaban a no hacer nada,
    // con las otras dos historias ya inalcanzables por ningún camino.
    gate = () async => throw StateError('el gate se cayó');
    await abrir(tester, <Story>[_photo('s1'), _photo('s2'), _photo('s3')]);

    await tester.tap(find.byKey(const ValueKey<String>('blind-viewer-like')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(acciones, isEmpty, reason: 'el gate falló: no se manda nada');

    await tester.tapAt(_derecha);
    await tester.pump();
    expect(vistas, <String>['s1', 's2']);

    await cerrar(tester);
  });
}
