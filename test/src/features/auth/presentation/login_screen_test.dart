import 'package:attra/src/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  testWidgets('empieza con una elección simple y sin pedir el teléfono',
      (WidgetTester tester) async {
    _usePortraitViewport(tester);
    await tester.pumpWidget(const _LoginHost());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('login-methods')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('login-phone-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('login-google-button')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey<String>('login-phone')), findsNothing);
    expect(find.byKey(const ValueKey<String>('login-code')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Guideline 1.2: sin aceptar el EULA no se puede registrar ni iniciar sesión',
    (WidgetTester tester) async {
      _usePortraitViewport(tester);
      bool googlePressed = false;
      int termsAccepted = 0;

      await tester.pumpWidget(
        _LoginHost(
          onGooglePressed: () => googlePressed = true,
          onTermsAccepted: () => termsAccepted++,
        ),
      );
      await tester.pumpAndSettle();

      // La aceptación se presenta ANTES de cualquier método de acceso.
      expect(
        find.byKey(const ValueKey<String>('login-terms-gate')),
        findsOneWidget,
      );
      expect(find.textContaining('tolerancia cero'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('legal-link-terms')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('legal-link-privacy')),
        findsOneWidget,
      );

      // Sin marcar la casilla, ningún método de acceso avanza.
      await _tap(tester, 'login-google-button');
      expect(googlePressed, isFalse);
      expect(termsAccepted, 0);

      await _tap(tester, 'login-phone-button');
      expect(find.byKey(const ValueKey<String>('login-phone')), findsNothing);
      expect(
        find.textContaining('acepta las Condiciones de uso'),
        findsOneWidget,
      );

      // Tras aceptar, el acceso funciona.
      await _acceptTerms(tester);
      expect(termsAccepted, 0);
      await _tap(tester, 'login-google-button');
      expect(googlePressed, isTrue);
      expect(termsAccepted, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Apple también requiere una aceptación explícita',
      (WidgetTester tester) async {
    _usePortraitViewport(tester);
    bool applePressed = false;
    int termsAccepted = 0;
    await tester.pumpWidget(_LoginHost(
      onApplePressed: () => applePressed = true,
      onTermsAccepted: () => termsAccepted++,
    ));
    await tester.pumpAndSettle();

    await _tap(tester, 'login-apple-blocked');
    expect(applePressed, isFalse);
    expect(termsAccepted, 0);
    expect(
        find.textContaining('acepta las Condiciones de uso'), findsOneWidget);

    await _acceptTerms(tester);
    final Finder appleButton = find.byType(SignInWithAppleButton);
    await tester.ensureVisible(appleButton);
    await tester.tap(appleButton);
    await tester.pumpAndSettle();
    expect(applePressed, isTrue);
    expect(termsAccepted, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
      'un SMS pendiente no permite saltarse los términos al recrear login',
      (WidgetTester tester) async {
    _usePortraitViewport(tester);
    String? verifiedCode;
    await tester.pumpWidget(_LoginHost(
      initialPhoneCodeSent: true,
      onVerifyPhoneCode: (String value) => verifiedCode = value,
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>('login-terms-gate')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('login-code')), findsNothing);
    await _tap(tester, 'login-phone-button');
    expect(find.byType(TextField), findsNothing);
    expect(verifiedCode, isNull);

    await _acceptTerms(tester);
    await _tap(tester, 'login-phone-button');
    expect(find.byKey(const ValueKey<String>('login-code')), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Verificar código'));
    await tester.pumpAndSettle();
    expect(verifiedCode, '123456');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'abre teléfono, conserva el número al pasar a SMS y entrega ambos valores',
    (WidgetTester tester) async {
      _usePortraitViewport(tester);
      String? sentPhone;
      String? verifiedCode;

      await tester.pumpWidget(
        _LoginHost(
          onSendPhoneCode: (String value) => sentPhone = value,
          onVerifyPhoneCode: (String value) => verifiedCode = value,
        ),
      );
      await tester.pumpAndSettle();
      await _acceptTerms(tester);
      await _tap(tester, 'login-phone-button');

      expect(find.byKey(const ValueKey<String>('login-phone')), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '600 111 222');
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(sentPhone, '+34600111222');
      expect(find.byKey(const ValueKey<String>('login-code')), findsOneWidget);
      expect(find.textContaining('+34600111222'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Verificar código'));
      await tester.pumpAndSettle();

      expect(verifiedCode, '123456');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no desborda en un viewport pequeño con texto al doble',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const _LoginHost(textScale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _acceptTerms(tester);
    await _tap(tester, 'login-phone-button');
    expect(find.byKey(const ValueKey<String>('login-phone')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '600111222');
    await tester.pump();
    await tester.ensureVisible(find.text('Continuar'));
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('login-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _usePortraitViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// La pantalla es scrollable: hay que asegurar visibilidad antes de tocar.
Future<void> _tap(WidgetTester tester, String key) async {
  final Finder finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Marca la aceptación del EULA, obligatoria antes de cualquier método de
/// acceso (App Store Guideline 1.2).
Future<void> _acceptTerms(WidgetTester tester) async {
  // La fila completa puede ser más alta que el viewport con texto ampliado.
  // El control real conserva un objetivo visible de tamaño táctil.
  final Finder checkbox = find.byType(Checkbox);
  await tester.ensureVisible(checkbox);
  await tester.pumpAndSettle();
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

class _LoginHost extends StatefulWidget {
  const _LoginHost({
    this.onGooglePressed,
    this.onApplePressed,
    this.onTermsAccepted,
    this.onSendPhoneCode,
    this.onVerifyPhoneCode,
    this.textScale = 1,
    this.initialPhoneCodeSent = false,
  });

  final VoidCallback? onGooglePressed;
  final VoidCallback? onApplePressed;
  final VoidCallback? onTermsAccepted;
  final ValueChanged<String>? onSendPhoneCode;
  final ValueChanged<String>? onVerifyPhoneCode;
  final double textScale;
  final bool initialPhoneCodeSent;

  @override
  State<_LoginHost> createState() => _LoginHostState();
}

class _LoginHostState extends State<_LoginHost> {
  late bool _phoneCodeSent = widget.initialPhoneCodeSent;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(widget.textScale),
          ),
          child: child!,
        );
      },
      home: LoginScreen(
        phoneCodeSent: _phoneCodeSent,
        onGooglePressed: () => widget.onGooglePressed?.call(),
        onApplePressed: () => widget.onApplePressed?.call(),
        onTermsAccepted: widget.onTermsAccepted,
        onSendPhoneCode: (String value) {
          widget.onSendPhoneCode?.call(value);
          setState(() => _phoneCodeSent = true);
        },
        onVerifyPhoneCode: (String value) {
          widget.onVerifyPhoneCode?.call(value);
        },
      ),
    );
  }
}
