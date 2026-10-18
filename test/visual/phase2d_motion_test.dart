import 'dart:io';
import 'dart:ui' as ui;

import 'package:attra/src/features/match/presentation/match_created_dialog.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic frame inspection on Flutter's widget engine. This fixture has
/// no user photographs, Firebase calls or device frame-time measurements.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (String family, Future<ByteData> data)
        in <(String, Future<ByteData>)>[
      ('Manrope', rootBundle.load('assets/fonts/manrope/Manrope-Variable.ttf')),
      (
        'Roboto',
        File('test/visual/fonts/Roboto-Variable.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes))
      ),
      ('MaterialIcons', rootBundle.load('fonts/MaterialIcons-Regular.otf')),
    ]) {
      await (FontLoader(family)..addFont(data)).load();
    }
  });

  for (final bool reduced in <bool>[false, true]) {
    testWidgets('match preserves route clocks and immediate action ($reduced)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int opened = 0;
      final GlobalKey boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Builder(
              builder: (BuildContext context) => Scaffold(
                    body: Center(
                        child: TextButton(
                      onPressed: () => showMatchCreatedDialog(context,
                          name: 'Alex',
                          photoUrl: null,
                          currentUserPhotoUrl: null,
                          hasAttra: true,
                          sharedInterests: const <String>['Arte', 'Viajes'],
                          onOpenChat: () => opened++),
                      child: const Text('Abrir match'),
                    )),
                  )),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir match'));
      await tester.pump();
      await tester.pump();
      final PageRoute<dynamic> route = ModalRoute.of(tester.element(find.text(
          'A ti y a Alex les gusta mutuamente',
          skipOffstage: false)))! as PageRoute<dynamic>;
      expect(route.transitionDuration, const Duration(milliseconds: 200));
      expect(
          route.reverseTransitionDuration, const Duration(milliseconds: 140));
      final String prefix = reduced ? 'match-reduced' : 'match';
      await _capture(tester, boundary, '$prefix-000');
      await tester.pump(const Duration(milliseconds: 40));
      await _capture(tester, boundary, '$prefix-040');
      await tester.pump(const Duration(milliseconds: 60));
      await _capture(tester, boundary, '$prefix-100');
      await tester.pump(const Duration(milliseconds: 100));
      await _capture(tester, boundary, '$prefix-200');
      expect(find.text('Enviar mensaje'), findsOneWidget);
      await tester.tap(find.text('Enviar mensaje'));
      // Callback occurs on activation, independently of the exit transition.
      expect(opened, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      await _capture(tester, boundary, '$prefix-exit-070');
      await tester.pumpAndSettle();
      expect(find.text('Abrir match'), findsOneWidget);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const String output = String.fromEnvironment('ATTRA_MOTION_OUTPUT');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final RenderRepaintBoundary render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image frame = await render.toImage();
    final ByteData png =
        (await frame.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(png.buffer.asUint8List());
    frame.dispose();
  });
}
