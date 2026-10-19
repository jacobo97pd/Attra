import 'package:attra/src/features/match/presentation/photo_response_sheet.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  required PhotoResponseKind kind,
  required int balance,
  required bool canComment,
  required ValueChanged<PhotoResponseResult?> onResult,
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async => onResult(await PhotoResponseSheet.show(
            context,
            kind: kind,
            name: 'Alexandra María de la Fuente',
            photoUrl: '',
            attraBalance: balance,
            canComment: canComment,
          )),
          child: const Text('Abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'comment sheet supports 200 percent text and keyboard at 320 wide',
      (WidgetTester tester) async {
    PhotoResponseResult? result;
    await _openSheet(tester,
        kind: PhotoResponseKind.like,
        balance: 0,
        canComment: true,
        scale: 2,
        keyboard: 240,
        onResult: (PhotoResponseResult? value) => result = value);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Me gusta esta foto  ');
    final Finder submit =
        find.byKey(const ValueKey<String>('photo-response-submit-like'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(result?.kind, PhotoResponseKind.like);
    expect(result?.comment, 'Me gusta esta foto');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Attra remains disabled without balance and Plus comment stays gated',
      (WidgetTester tester) async {
    PhotoResponseResult? result;
    await _openSheet(tester,
        kind: PhotoResponseKind.attra,
        balance: 0,
        canComment: false,
        onResult: (PhotoResponseResult? value) => result = value);

    final Finder submit =
        find.byKey(const ValueKey<String>('photo-response-submit-attra'));
    expect(tester.widget<AttraGlassPillButton>(submit).onPressed, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Comentario con Plus'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoResponseSheet), findsNothing);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('funded Attra keeps its kind and sends no comment without Plus',
      (WidgetTester tester) async {
    PhotoResponseResult? result;
    await _openSheet(tester,
        kind: PhotoResponseKind.attra,
        balance: 2,
        canComment: false,
        onResult: (PhotoResponseResult? value) => result = value);

    final Finder submit =
        find.byKey(const ValueKey<String>('photo-response-submit-attra'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(result?.kind, PhotoResponseKind.attra);
    expect(result?.comment, isNull);
    expect(tester.takeException(), isNull);
  });
}
