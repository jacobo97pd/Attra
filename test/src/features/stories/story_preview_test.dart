import 'dart:io';

import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/domain/story_composer.dart';
import 'package:attra/src/features/stories/presentation/story_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Una historia es PÚBLICA y dura 72 h. El compositor publicaba en cuanto
/// tocabas una miniatura de la cuadrícula —el mismo gesto que harías solo para
/// verla más grande—, así que un toque de más la sacaba a la calle sin vuelta
/// atrás. Estos tests fijan que publicar exige un acto deliberado.
StoryDraft _draft() => StoryDraft(
      file: XFile('/tmp/no-existe.jpg'),
      type: StoryMediaType.image,
    );

/// `Image.file` necesita un fichero real en disco; en un widget test no hay
/// ninguno, así que se sustituye el pintado. Lo que se prueba es la DECISIÓN,
/// no el decodificador de imágenes de Flutter.
Widget _harness({required void Function(bool?) onResult}) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final bool? result = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => StoryPreviewScreen(
                    draft: _draft(),
                    imageBuilder: (File _) => const ColoredBox(
                      color: Colors.grey,
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              );
              onResult(result);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('la previsualización NO publica por sí sola', (
    WidgetTester tester,
  ) async {
    bool? result;
    await tester.pumpWidget(_harness(onResult: (bool? r) => result = r));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Se ve la foto y el botón, pero no ha pasado nada todavía.
    expect(find.byKey(const Key('story-preview-publish')), findsOneWidget);
    expect(result, isNull, reason: 'nadie ha confirmado aún');
  });

  testWidgets('solo publica al pulsar Publicar', (WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(_harness(onResult: (bool? r) => result = r));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('story-preview-publish')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('volver atrás descarta y NO publica', (
    WidgetTester tester,
  ) async {
    bool? result;
    await tester.pumpWidget(_harness(onResult: (bool? r) => result = r));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('story-preview-back')));
    await tester.pumpAndSettle();

    expect(
      result,
      isFalse,
      reason: 'descartar tiene que ser distinguible de confirmar: si volviera '
          'null y el compositor lo tratara como sí, se publicaría al salir',
    );
  });

  testWidgets('el gesto de retroceso del sistema tampoco publica', (
    WidgetTester tester,
  ) async {
    // En iOS se sale deslizando desde el borde, y eso hace pop SIN resultado.
    // El compositor tiene que leerlo como "no publiques".
    bool? result;
    bool llamado = false;
    await tester.pumpWidget(_harness(onResult: (bool? r) {
      result = r;
      llamado = true;
    }));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();

    expect(llamado, isTrue);
    expect(result, isNull);
  });
}
