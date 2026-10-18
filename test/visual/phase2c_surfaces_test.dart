import 'dart:io';
import 'dart:ui' as ui;

import 'package:attra/src/features/auth/presentation/login_screen.dart';
import 'package:attra/src/features/connection_lab/presentation/connection_lab_screen.dart';
import 'package:attra/src/features/connection_lab/presentation/demo_challenge_screen.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:attra/src/features/monetization/presentation/paywall_screen.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/profile/presentation/profile_view_screen.dart';
import 'package:attra/src/features/tutorial/presentation/tutorial_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real Flutter screens with local fixtures. These are widget-engine renders,
/// not Android/iOS device screenshots and not an authenticated production run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IapService store;
  setUp(() => store = IapService(iap: _NoStore()));
  tearDown(() => store.dispose());
  setUpAll(() async {
    final FontLoader display = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Variable.ttf'));
    await display.load();
    final FontLoader body = FontLoader('Roboto')
      ..addFont(File('test/visual/fonts/Roboto-Variable.ttf')
          .readAsBytes()
          .then((List<int> bytes) =>
              ByteData.sublistView(Uint8List.fromList(bytes))));
    await body.load();
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  final Map<String, Widget Function()> screens = <String, Widget Function()>{
    'login': () => LoginScreen(
          onGooglePressed: () {},
          onApplePressed: () {},
          onSendPhoneCode: (_) {},
          onVerifyPhoneCode: (_) {},
          phoneCodeSent: false,
        ),
    'tutorial': () => const TutorialScreen(),
    'connection-lab': () => Scaffold(
          appBar: AppBar(title: const Text('Attra')),
          body: ConnectionLabScreen(onDiscover: () {}, onOpenPlay: () {}),
        ),
    'challenge': () => const DemoChallengeScreen(),
    'plans': () =>
        PaywallScreen(currentTier: SubscriptionTier.free, iapService: store),
    'public-profile': () => ProfileViewScreen(
          profile: SeedProfile.fromMap('visual-fixture', <String, dynamic>{
            'displayName': 'María del Carmen',
            'city': 'Madrid',
            'country': 'España',
            'bio':
                'Las librerías, las sobremesas largas y los planes improvisados.',
            'interests': <String>['Arte', 'Viajes', 'Lectura'],
          }),
        ),
  };
  for (final (String name, Size size) in <(String, Size)>[
    ('phone', const Size(390, 844)),
    ('tablet', const Size(1024, 768)),
  ]) {
    for (final MapEntry<String, Widget Function()> screen in screens.entries) {
      testWidgets('${screen.key} stays usable on $name',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final GlobalKey boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.dark,
            debugShowCheckedModeBanner: false,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: screen.value(),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/images/ATTRA.png'),
            boundary.currentContext!));
        await tester.pumpAndSettle();
        const String output = String.fromEnvironment('ATTRA_REVIEW_OUTPUT');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final RenderRepaintBoundary render = boundary.currentContext!
                .findRenderObject()! as RenderRepaintBoundary;
            final ui.Image capture = await render.toImage();
            final ByteData png =
                (await capture.toByteData(format: ui.ImageByteFormat.png))!;
            final Directory folder =
                await Directory(output).create(recursive: true);
            await File('${folder.path}/${screen.key}-$name.png')
                .writeAsBytes(png.buffer.asUint8List());
            capture.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}

class _NoStore implements InAppPurchase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Read-only visual fixture');
}
