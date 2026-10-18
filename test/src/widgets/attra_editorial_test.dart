import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_buttons.dart';
import 'package:attra/src/widgets/attra_editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets('notas conservan contenido y acciones a320/200% en $brightness',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int actions = 0;
      await tester.pumpWidget(MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AttraContentFrame(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    AttraSectionHeading(
                      title: 'María del Carmen y sus historias',
                      subtitle: 'Las cosas que merece la pena compartir',
                      trailing: TextButton(
                        onPressed: () => actions++,
                        child: const Text('Editar mi perfil'),
                      ),
                    ),
                    const AttraPromptNote(
                      question: 'Un plan que nunca falla',
                      answer:
                          'Perderme en una librería y compartir lo que encuentro.',
                    ),
                    const AttraPhotoNote(
                      eyebrow: 'Un comentario sobre tu foto',
                      title: 'María del Carmen',
                      body: '¿Dónde encontraste esa librería?',
                      photo: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: ColoredBox(color: Colors.grey),
                      ),
                    ),
                    AttraPrimaryButton(
                      label: 'Continuar esta conversación',
                      onPressed: () => actions++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Editar mi perfil'));
      expect(actions, 1);
      final Finder primary = find.byType(AttraPrimaryButton);
      await tester.ensureVisible(primary);
      await tester.pumpAndSettle();
      expect(tester.getSize(primary).height, greaterThanOrEqualTo(52));
      await tester.tap(find.text('Continuar esta conversación'));
      expect(actions, 2);
      expect(find.text('¿Dónde encontraste esa librería?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('columna mantiene una anchura de lectura en ventanas grandes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: AttraContentFrame(
          child: AttraPromptNote(
            key: ValueKey<String>('reading-note'),
            question: 'Mi lugar favorito',
            answer: 'Donde empieza una buena conversación.',
          ),
        ),
      ),
    ));
    final Rect note =
        tester.getRect(find.byKey(const ValueKey<String>('reading-note')));
    expect(note.width, 680);
    expect(note.center.dx, 600);
  });

  testWidgets('acción ocupada conserva etiqueta y respeta movimiento reducido',
      (WidgetTester tester) async {
    int actions = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: AttraPrimaryButton(
            label: 'Guardar cambios',
            loading: true,
            onPressed: () => actions++,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Guardar cambios'));
    expect(actions, 0);
    expect(find.text('Guardar cambios'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
