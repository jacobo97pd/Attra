import 'dart:math' as math;

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../theme/app_spacing.dart';
import '../../../widgets/legal_links_row.dart';
import 'login_video_background.dart';

const Color _loginPaper = Color(0xFFF7F7F7);
const Color _loginSurface = Colors.white;
const Color _loginInk = Color(0xFF171717);
const Color _loginMuted = Color(0xFF666666);
const Color _loginLine = Color(0xFFDADADA);
const Color _loginInkSoft = Color(0xFFECECEC);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onGooglePressed,
    required this.onApplePressed,
    required this.onSendPhoneCode,
    required this.onVerifyPhoneCode,
    required this.phoneCodeSent,
    this.isLoading = false,
    this.errorMessage,
  });

  final VoidCallback onGooglePressed;
  final VoidCallback onApplePressed;

  /// Recibe el número completo con prefijo, por ejemplo `+34600111222`.
  final ValueChanged<String> onSendPhoneCode;
  final ValueChanged<String> onVerifyPhoneCode;
  final bool phoneCodeSent;
  final bool isLoading;
  final String? errorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginStage { methods, phone, code }

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _phoneController;
  late final TextEditingController _smsCodeController;
  late final FocusNode _phoneFocus;
  late final FocusNode _smsFocus;
  late _LoginStage _stage;

  String _dialCode = '+34';
  String _countryCode = 'ES';
  String? _validationMessage;

  /// Guideline 1.2: nadie puede registrarse ni iniciar sesion sin aceptar
  /// EXPLICITAMENTE las Condiciones de uso (EULA), que incluyen la tolerancia
  /// cero con el contenido ofensivo y los usuarios abusivos.
  bool _termsAccepted = false;
  bool _termsWarning = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController()..addListener(_onInputChanged);
    _smsCodeController = TextEditingController()..addListener(_onInputChanged);
    _phoneFocus = FocusNode()..addListener(_onInputChanged);
    _smsFocus = FocusNode();
    _stage = widget.phoneCodeSent ? _LoginStage.code : _LoginStage.methods;
    if (_stage == _LoginStage.code) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSms());
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phoneCodeSent && !oldWidget.phoneCodeSent) {
      setState(() {
        _stage = _LoginStage.code;
        _validationMessage = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSms());
    }
  }

  @override
  void dispose() {
    _phoneController
      ..removeListener(_onInputChanged)
      ..dispose();
    _smsCodeController
      ..removeListener(_onInputChanged)
      ..dispose();
    _phoneFocus
      ..removeListener(_onInputChanged)
      ..dispose();
    _smsFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    setState(() => _validationMessage = null);
  }

  String get _fullPhoneNumber {
    final String digits = _phoneController.text
        .trim()
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '$_dialCode$digits';
  }

  bool get _canSendPhone =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_fullPhoneNumber);

  bool get _canVerifyCode => _smsCodeController.text.trim().length >= 4;

  String get _phoneDestination {
    if (_phoneController.text.trim().isEmpty) {
      return 'al número que indicaste';
    }
    return 'a $_fullPhoneNumber';
  }

  void _focusPhone() {
    if (mounted) _phoneFocus.requestFocus();
  }

  void _focusSms() {
    if (mounted) _smsFocus.requestFocus();
  }

  /// Guideline 1.2: puerta de entrada. Si el usuario no ha aceptado el EULA no
  /// se ejecuta NINGUN metodo de acceso; se resalta la casilla en su lugar.
  void _guardTerms(VoidCallback action) {
    if (widget.isLoading) return;
    if (!_termsAccepted) {
      setState(() {
        _termsWarning = true;
        _validationMessage = 'Para continuar, acepta las Condiciones de uso '
            '(EULA) y la Política de privacidad.';
      });
      return;
    }
    action();
  }

  void _toggleTerms(bool? value) {
    if (widget.isLoading) return;
    setState(() {
      _termsAccepted = value ?? false;
      if (_termsAccepted) {
        _termsWarning = false;
        _validationMessage = null;
      }
    });
  }

  void _openPhone() {
    if (widget.isLoading) return;
    setState(() {
      _stage = _LoginStage.phone;
      _validationMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusPhone());
  }

  void _showMethods() {
    if (widget.isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _LoginStage.methods;
      _validationMessage = null;
    });
  }

  void _editPhone() {
    if (widget.isLoading) return;
    setState(() {
      _stage = _LoginStage.phone;
      _validationMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusPhone());
  }

  void _sendCode() {
    if (widget.isLoading) return;
    if (!_canSendPhone) {
      setState(() {
        _validationMessage =
            'Introduce un número válido con su prefijo internacional.';
      });
      _phoneFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _validationMessage = null);
    widget.onSendPhoneCode(_fullPhoneNumber);
  }

  void _verifyCode() {
    if (widget.isLoading) return;
    final String code = _smsCodeController.text.trim();
    if (code.length < 4) {
      setState(() {
        _validationMessage = 'Introduce el código completo del SMS.';
      });
      _smsFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _validationMessage = null);
    widget.onVerifyPhoneCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final bool showApple =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0C0D10),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0D10),
        resizeToAvoidBottomInset: true,
        body: LoginVideoBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double verticalPadding = 24 + (bottomInset > 0 ? 18 : 28);
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    bottomInset > 0 ? 18 : 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          math.max(0, constraints.maxHeight - verticalPadding),
                    ),
                    child: IntrinsicHeight(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Align(
                                alignment: Alignment.center,
                                child: _AttraWordmark(),
                              ),
                              const SizedBox(height: 24),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (
                                  Widget child,
                                  Animation<double> animation,
                                ) {
                                  final Animation<Offset> slide = Tween<Offset>(
                                    begin: const Offset(0.025, 0),
                                    end: Offset.zero,
                                  ).animate(animation);
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: slide,
                                      child: child,
                                    ),
                                  );
                                },
                                child: switch (_stage) {
                                  _LoginStage.methods =>
                                    _buildMethods(showApple),
                                  _LoginStage.phone => _buildPhoneEntry(),
                                  _LoginStage.code => _buildCodeEntry(),
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethods(bool showApple) {
    final ThemeData theme = Theme.of(context);
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final bool compactHeight = screenHeight < 700;
    final double actionGap = math.max(
      44,
      screenHeight - (showApple ? 566 : 500),
    );
    return Column(
      key: const ValueKey<String>('login-methods'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: compactHeight ? 28 : 90),
        Text(
          'Menos ruido.\nMás conexión.',
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontSize: 46,
            height: 0.98,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.8,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Conoce personas con intención y deja que la conversación haga el resto.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 17,
            height: 1.45,
          ),
        ),
        // El gate del EULA ocupa el espacio que antes era aire, para que los
        // botones de acceso sigan cayendo en la misma zona de la pantalla.
        SizedBox(height: math.max(20, actionGap - 168)),
        // Guideline 1.2: la aceptacion del EULA se presenta ANTES de cualquier
        // metodo de registro/acceso y bloquea todos ellos hasta marcarla.
        _TermsGate(
          accepted: _termsAccepted,
          warning: _termsWarning,
          enabled: !widget.isLoading,
          onChanged: _toggleTerms,
        ),
        const SizedBox(height: 16),
        _AuthButton(
          key: const ValueKey<String>('login-phone-button'),
          label: 'Continuar con teléfono',
          leading: const Icon(Icons.phone_outlined, size: 21),
          style: _AuthButtonStyle.light,
          enabled: _termsAccepted,
          onPressed: widget.isLoading ? null : () => _guardTerms(_openPhone),
        ),
        if (showApple) ...<Widget>[
          const SizedBox(height: 10),
          Opacity(
            opacity: widget.isLoading ? 0.45 : (_termsAccepted ? 1 : 0.48),
            // Sin EULA aceptado interceptamos el toque para avisar en vez de
            // lanzar el flujo nativo de Apple.
            child: _termsAccepted
                ? IgnorePointer(
                    ignoring: widget.isLoading,
                    child: SignInWithAppleButton(
                      onPressed: widget.onApplePressed,
                      style: SignInWithAppleButtonStyle.white,
                      height: 56,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppSpacing.radiusLg),
                      ),
                      text: 'Continuar con Apple',
                    ),
                  )
                : GestureDetector(
                    key: const ValueKey<String>('login-apple-blocked'),
                    onTap: () => _guardTerms(widget.onApplePressed),
                    child: IgnorePointer(
                      child: SignInWithAppleButton(
                        onPressed: widget.onApplePressed,
                        style: SignInWithAppleButtonStyle.white,
                        height: 56,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppSpacing.radiusLg),
                        ),
                        text: 'Continuar con Apple',
                      ),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 10),
        _AuthButton(
          key: const ValueKey<String>('login-google-button'),
          label: widget.isLoading
              ? 'Conectando con Google…'
              : 'Continuar con Google',
          leading: const _GoogleMark(),
          style: _AuthButtonStyle.glass,
          loading: widget.isLoading,
          enabled: _termsAccepted,
          onPressed: widget.isLoading
              ? null
              : () => _guardTerms(widget.onGooglePressed),
        ),
        if (_visibleError != null) ...<Widget>[
          const SizedBox(height: 14),
          _LoginError(message: _visibleError!),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPhoneEntry() {
    final ThemeData theme = Theme.of(context);
    final MediaQueryData media = MediaQuery.of(context);
    final double panelGap = media.viewInsets.bottom > 0
        ? 24
        : math.max(24, media.size.height - 540);
    return Column(
      key: const ValueKey<String>('login-phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: panelGap),
        _LoginPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _LoginBackButton(onPressed: _showMethods),
              const SizedBox(height: 24),
              Text(
                '¿Cuál es tu número?',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: _loginInk,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Te enviaremos un SMS para comprobar que eres tú. No lo '
                'mostraremos en tu perfil.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _loginMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              _PhoneField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                enabled: !widget.isLoading,
                countryCode: _countryCode,
                onCountryChanged: (CountryCode country) {
                  setState(() {
                    _dialCode = country.dialCode ?? _dialCode;
                    _countryCode = country.code ?? _countryCode;
                    _validationMessage = null;
                  });
                },
                onSubmitted: (_) => _sendCode(),
              ),
              if (_visibleError != null) ...<Widget>[
                const SizedBox(height: 14),
                _LoginError(message: _visibleError!),
              ],
              const SizedBox(height: 18),
              _AuthButton(
                label: widget.isLoading ? 'Enviando código…' : 'Continuar',
                leading: const Icon(Icons.arrow_forward_rounded, size: 21),
                style: _AuthButtonStyle.dark,
                loading: widget.isLoading,
                onPressed:
                    !widget.isLoading && _canSendPhone ? _sendCode : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCodeEntry() {
    final ThemeData theme = Theme.of(context);
    final MediaQueryData media = MediaQuery.of(context);
    final double panelGap = media.viewInsets.bottom > 0
        ? 24
        : math.max(24, media.size.height - 650);
    return Column(
      key: const ValueKey<String>('login-code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: panelGap),
        _LoginPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _LoginBackButton(onPressed: _editPhone),
              const SizedBox(height: 24),
              Text(
                'Revisa tus mensajes',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: _loginInk,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Introduce el código que hemos enviado $_phoneDestination.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _loginMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              _SmsCodeField(
                controller: _smsCodeController,
                focusNode: _smsFocus,
                enabled: !widget.isLoading,
                onSubmitted: (_) => _verifyCode(),
              ),
              if (_visibleError != null) ...<Widget>[
                const SizedBox(height: 14),
                _LoginError(message: _visibleError!),
              ],
              const SizedBox(height: 18),
              _AuthButton(
                label: widget.isLoading ? 'Comprobando…' : 'Verificar código',
                leading: const Icon(Icons.check_rounded, size: 21),
                style: _AuthButtonStyle.dark,
                loading: widget.isLoading,
                onPressed:
                    !widget.isLoading && _canVerifyCode ? _verifyCode : null,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed:
                    widget.isLoading || !_canSendPhone ? null : _sendCode,
                style: TextButton.styleFrom(
                  foregroundColor: _loginInk,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(
                  'No me ha llegado · Reenviar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? get _visibleError => _validationMessage ?? widget.errorMessage;
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _loginPaper,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AttraWordmark extends StatelessWidget {
  const _AttraWordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Attra',
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: Image.asset(
          'assets/images/ATTRA.png',
          height: 34,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _LoginBackButton extends StatelessWidget {
  const _LoginBackButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: onPressed,
        tooltip: 'Atrás',
        style: IconButton.styleFrom(
          foregroundColor: _loginInk,
          backgroundColor: _loginSurface,
          side: const BorderSide(color: _loginLine),
          minimumSize: const Size(48, 48),
        ),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    );
  }
}

/// Aceptacion OBLIGATORIA del EULA antes de registrarse o iniciar sesion
/// (App Store Guideline 1.2). Incluye la clausula de tolerancia cero y enlaces
/// FUNCIONALES a las Condiciones de uso y a la Politica de privacidad.
class _TermsGate extends StatelessWidget {
  const _TermsGate({
    required this.accepted,
    required this.warning,
    required this.enabled,
    required this.onChanged,
  });

  final bool accepted;
  final bool warning;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color border = warning
        ? const Color(0xFFFF6B81)
        : Colors.white.withValues(alpha: accepted ? 0.55 : 0.28);

    return Container(
      key: const ValueKey<String>('login-terms-gate'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x660C0D10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: border, width: warning ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('login-terms-checkbox'),
            onTap: enabled ? () => onChanged(!accepted) : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    checked: accepted,
                    label: 'Acepto las Condiciones de uso y la Política de '
                        'privacidad',
                    child: Checkbox(
                      value: accepted,
                      onChanged: enabled ? onChanged : null,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.75),
                        width: 1.6,
                      ),
                      checkColor: const Color(0xFF0C0D10),
                      fillColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<WidgetState> states) =>
                            states.contains(WidgetState.selected)
                                ? Colors.white
                                : Colors.transparent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tengo 18 años o más y acepto las Condiciones de uso '
                      '(EULA) y la Política de privacidad. Attra tiene '
                      'tolerancia cero con el contenido ofensivo y con los '
                      'usuarios abusivos.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.only(left: 34),
            child: AttraLegalLinksRow(
              color: Colors.white,
              fontSize: 12,
              alignment: WrapAlignment.start,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AuthButtonStyle { light, glass, dark }

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onPressed,
    this.style = _AuthButtonStyle.glass,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onPressed;
  final _AuthButtonStyle style;
  final bool loading;

  /// Cuando es false el boton se ve atenuado pero SIGUE siendo pulsable, para
  /// que el toque avise de que falta aceptar el EULA (Guideline 1.2).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool active = onPressed != null && !loading;
    final (Color background, Color foreground, Color border) = switch (style) {
      _AuthButtonStyle.light => (
          Colors.white,
          _loginInk,
          Colors.white,
        ),
      _AuthButtonStyle.glass => (
          const Color(0x660C0D10),
          Colors.white,
          Colors.white.withValues(alpha: 0.62),
        ),
      _AuthButtonStyle.dark => (
          _loginInk,
          _loginPaper,
          _loginInk,
        ),
    };

    return Opacity(
      opacity: (active && enabled) ? 1 : 0.48,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: active ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconTheme(
                    data: IconThemeData(color: foreground),
                    child: loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: foreground,
                            ),
                          )
                        : leading,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 21,
      height: 21,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect ring = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.12,
      size.width * 0.76,
      size.height * 0.76,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.17
      ..strokeCap = StrokeCap.butt;

    void arc(Color color, double startDegrees, double sweepDegrees) {
      paint.color = color;
      canvas.drawArc(
        ring,
        startDegrees * math.pi / 180,
        sweepDegrees * math.pi / 180,
        false,
        paint,
      );
    }

    arc(const Color(0xFF4285F4), -45, 92);
    arc(const Color(0xFF34A853), 47, 88);
    arc(const Color(0xFFFBBC05), 135, 56);
    arc(const Color(0xFFEA4335), 191, 124);

    paint
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.17
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.50),
      Offset(size.width * 0.90, size.height * 0.50),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleMarkPainter oldDelegate) => false;
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.countryCode,
    required this.onCountryChanged,
    required this.enabled,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String countryCode;
  final ValueChanged<CountryCode> onCountryChanged;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'Número de teléfono',
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: _loginSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: focusNode.hasFocus ? _loginInk : _loginLine,
            width: focusNode.hasFocus ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            CountryCodePicker(
              onChanged: onCountryChanged,
              initialSelection: countryCode,
              favorite: const <String>['+34', '+1', '+52', '+57', '+54'],
              showCountryOnly: false,
              showOnlyCountryWhenClosed: false,
              alignLeft: false,
              enabled: enabled,
              padding: EdgeInsets.zero,
              flagWidth: 24,
              textStyle: const TextStyle(
                color: _loginInk,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              dialogBackgroundColor: _loginSurface,
              barrierColor: _loginInk.withValues(alpha: 0.35),
              closeIcon: const Icon(
                Icons.close_rounded,
                color: _loginMuted,
              ),
              boxDecoration: BoxDecoration(
                color: _loginSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: _loginLine),
              ),
              dialogItemPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              dialogTextStyle: const TextStyle(
                color: _loginInk,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              searchStyle: const TextStyle(color: _loginInk),
              searchDecoration: InputDecoration(
                hintText: 'Buscar país',
                hintStyle: const TextStyle(color: _loginMuted),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _loginMuted),
                filled: true,
                fillColor: _loginPaper,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  borderSide: const BorderSide(color: _loginLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  borderSide: const BorderSide(
                    color: _loginInk,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 28, color: _loginLine),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[
                    AutofillHints.telephoneNumberNational,
                  ],
                  onSubmitted: onSubmitted,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-]')),
                    LengthLimitingTextInputFormatter(18),
                  ],
                  style: const TextStyle(
                    color: _loginInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: '600 111 222',
                    hintStyle: TextStyle(
                      color: _loginMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsCodeField extends StatelessWidget {
  const _SmsCodeField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      autofillHints: const <String>[AutofillHints.oneTimeCode],
      onSubmitted: onSubmitted,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
        color: _loginInk,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 9,
      ),
      decoration: InputDecoration(
        hintText: '••••••',
        hintStyle: TextStyle(
          color: _loginMuted.withValues(alpha: 0.35),
          fontSize: 25,
          letterSpacing: 9,
        ),
        labelText: 'Código SMS',
        labelStyle: const TextStyle(color: _loginMuted),
        floatingLabelStyle: const TextStyle(
          color: _loginInk,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: _loginSurface,
        counterText: '',
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: _loginLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: _loginInk, width: 1.6),
        ),
      ),
    );
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _loginInkSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.info_outline_rounded,
              color: _loginInk,
              size: 19,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: _loginInk,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
