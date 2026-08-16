import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La vista previa de la cámara salía ALARGADA en las dos cámaras.
///
/// La causa: `CameraPreview` iba suelto dentro de un `Stack(fit:
/// StackFit.expand)`, así que se estiraba hasta llenar la pantalla ignorando la
/// proporción del sensor. Las caras salían deformadas.
///
/// `CameraPreview` necesita un controlador nativo y no se puede montar en un
/// test, así que lo que se fija aquí es la ENVOLTURA: que el recorte por
/// `BoxFit.cover` conserva la proporción, y que los lados del sensor van
/// intercambiados (el sensor siempre reporta apaisado; la pantalla es vertical).
///
/// Réplica de la envoltura de `DeviceStoryCamera.preview()`.
Widget previewWrapper({required Size sensor, required Widget child}) {
  return ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        // Intercambiados a propósito: previewSize viene en coordenadas del
        // sensor, que es apaisado.
        width: sensor.height,
        height: sensor.width,
        child: child,
      ),
    ),
  );
}

void main() {
  /// Lo que ocupa el hijo en pantalla tras el recorte.
  Future<Size> renderedSize(
    WidgetTester tester, {
    required Size sensor,
    required Size screen,
  }) async {
    const Key inner = Key('preview');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: screen.width,
            height: screen.height,
            child: previewWrapper(
              sensor: sensor,
              child: const SizedBox.expand(key: inner),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(inner));
  }

  group('La proporción se conserva', () {
    testWidgets('un sensor 4:3 no se deforma en una pantalla 9:19.5', (
      WidgetTester tester,
    ) async {
      // El caso real: iPhone en vertical con un sensor apaisado.
      final Size rendered = await renderedSize(
        tester,
        sensor: const Size(1920, 1440), // sensor apaisado 4:3
        screen: const Size(390, 844), // iPhone en vertical
      );

      // Tras intercambiar los lados, el hijo es 1440x1920 = 3:4. Esa proporción
      // tiene que sobrevivir al escalado.
      expect(
        rendered.width / rendered.height,
        closeTo(1440 / 1920, 0.001),
        reason: 'si esto cambia, las caras salen alargadas',
      );
    });

    testWidgets('un sensor 16:9 tampoco se deforma', (
      WidgetTester tester,
    ) async {
      final Size rendered = await renderedSize(
        tester,
        sensor: const Size(1920, 1080),
        screen: const Size(390, 844),
      );

      expect(rendered.width / rendered.height, closeTo(1080 / 1920, 0.001));
    });
  });

  group('Cubre la pantalla sin dejar bandas', () {
    testWidgets('el resultado tapa todo el ancho y todo el alto', (
      WidgetTester tester,
    ) async {
      // `cover` recorta lo que sobra, pero NO puede dejar huecos: una banda
      // negra en una cámara a pantalla completa se ve como un fallo.
      const Size screen = Size(390, 844);
      final Size rendered = await renderedSize(
        tester,
        sensor: const Size(1920, 1440),
        screen: screen,
      );

      expect(rendered.width, greaterThanOrEqualTo(screen.width - 0.01));
      expect(rendered.height, greaterThanOrEqualTo(screen.height - 0.01));
    });

    testWidgets('también con la pantalla apaisada', (
      WidgetTester tester,
    ) async {
      const Size screen = Size(844, 390);
      final Size rendered = await renderedSize(
        tester,
        sensor: const Size(1920, 1440),
        screen: screen,
      );

      expect(rendered.width, greaterThanOrEqualTo(screen.width - 0.01));
      expect(rendered.height, greaterThanOrEqualTo(screen.height - 0.01));
    });
  });
}
