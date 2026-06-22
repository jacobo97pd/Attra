import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import 'login_video_background.dart';

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

  /// Recibe el número completo con prefijo, ej: "+34600111222"
  final ValueChanged<String> onSendPhoneCode;
  final ValueChanged<String> onVerifyPhoneCode;
  final bool phoneCodeSent;
  final bool isLoading;
  final String? errorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _phoneController;
  late final TextEditingController _smsCodeController;
  late final FocusNode _phoneFocus;
  late final FocusNode _smsFocus;

  // Las opciones de inicio empiezan OCULTAS tras el botón "Iniciar sesión" y
  // aparecen deslizándose de abajo hacia arriba al pulsarlo.
  late final AnimationController _revealController;
  late final Animation<Offset> _revealSlide;
  late final Animation<double> _revealFade;
  bool _revealed = false;

  String _dialCode = '+34';
  String _countryCode = 'ES';

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _smsCodeController = TextEditingController();
    _phoneFocus = FocusNode();
    _smsFocus = FocusNode();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _revealSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic));
    _revealFade = CurvedAnimation(
        parent: _revealController, curve: const Interval(0.1, 1.0));
    // Si ya hay paso de SMS o un error que mostrar, revela sin animar.
    if (widget.phoneCodeSent || widget.errorMessage != null) {
      _revealed = true;
      _revealController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si llega el paso de SMS o un error mientras está oculto, lo revelamos.
    if (!_revealed &&
        (widget.phoneCodeSent || widget.errorMessage != null)) {
      _reveal();
    }
  }

  void _reveal() {
    if (_revealed) return;
    setState(() => _revealed = true);
    _revealController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    _phoneFocus.dispose();
    _smsFocus.dispose();
    _revealController.dispose();
    super.dispose();
  }

  String get _fullPhoneNumber {
    final String digits = _phoneController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'^0+'), '');
    return '$_dialCode$digits';
  }

  void _sendCode() {
    if (widget.isLoading) return;
    final String phone = _fullPhoneNumber;
    if (phone.length < 8) return;
    widget.onSendPhoneCode(phone);
  }

  void _verifyCode() {
    if (widget.isLoading) return;
    final String code = _smsCodeController.text.trim();
    if (code.isEmpty) return;
    widget.onVerifyPhoneCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool showApple =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: LoginVideoBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Semantics(
                        label: 'Attra',
                        image: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusXl),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color:
                                    AppColors.attraRed.withValues(alpha: 0.26),
                                blurRadius: 34,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/ATTRA.png',
                            height: 58,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Conecta con personas que van en serio.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 36),

                    // CTA "Iniciar sesión" (oculta las opciones hasta pulsarlo).
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder:
                          (Widget child, Animation<double> anim) =>
                              FadeTransition(opacity: anim, child: child),
                      child: _revealed
                          ? const SizedBox.shrink(key: ValueKey<String>('gap'))
                          : Padding(
                              key: const ValueKey<String>('cta'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AttraPrimaryButton(
                                label: 'Iniciar sesión',
                                icon: Icons.login_rounded,
                                onPressed: _reveal,
                              ),
                            ),
                    ),

                    // Opciones reveladas: aparecen deslizándose de abajo arriba.
                    if (_revealed)
                      SlideTransition(
                        position: _revealSlide,
                        child: FadeTransition(
                          opacity: _revealFade,
                          child: _buildOptions(theme, showApple),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bloque con las formas de inicio de sesión (Google, Apple, teléfono/SMS).
  Widget _buildOptions(ThemeData theme, bool showApple) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Google.
        _SocialButton(
          label: widget.isLoading
              ? 'Iniciando sesión...'
              : 'Continuar con Google',
          loading: widget.isLoading,
          onPressed: widget.isLoading ? null : widget.onGooglePressed,
        ),
        if (showApple) ...<Widget>[
          const SizedBox(height: 12),
          IgnorePointer(
            ignoring: widget.isLoading,
            child: Opacity(
              opacity: widget.isLoading ? 0.55 : 1,
              child: SignInWithAppleButton(
                onPressed: widget.onApplePressed,
                style: SignInWithAppleButtonStyle.white,
                height: 54,
                borderRadius: const BorderRadius.all(
                    Radius.circular(AppSpacing.radiusPill)),
                text: 'Continuar con Apple',
              ),
            ),
          ),
        ],

        const SizedBox(height: 22),
        _Divider(theme: theme),
        const SizedBox(height: 22),

        // ── SECCIÓN TELÉFONO ──────────────────────────────────
        if (!widget.phoneCodeSent) ...<Widget>[
          // Campo: [🇪🇸 +34] [número]
          _PhoneField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            enabled: !widget.isLoading,
            dialCode: _dialCode,
            countryCode: _countryCode,
            onCountryChanged: (CountryCode c) => setState(() {
              _dialCode = c.dialCode ?? _dialCode;
              _countryCode = c.code ?? _countryCode;
            }),
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: 14),
          AttraPrimaryButton(
            label: 'Continuar con teléfono',
            icon: Icons.sms_rounded,
            loading: widget.isLoading,
            onPressed: widget.isLoading ? null : _sendCode,
          ),
        ] else ...<Widget>[
          // Número bloqueado (recap).
          _PhoneReadonly(
            phone: _fullPhoneNumber,
            onEdit: () => widget.onSendPhoneCode(_fullPhoneNumber),
          ),
          const SizedBox(height: 16),
          _SmsCodeField(
            controller: _smsCodeController,
            focusNode: _smsFocus,
            enabled: !widget.isLoading,
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 14),
          AttraPrimaryButton(
            label: 'Verificar código',
            icon: Icons.check_rounded,
            loading: widget.isLoading,
            onPressed: widget.isLoading ? null : _verifyCode,
          ),
          const SizedBox(height: 10),
          AttraGhostButton(
            label: 'Reenviar código SMS',
            onPressed: widget.isLoading ? null : _sendCode,
          ),
        ],

        // Error pill.
        if (widget.errorMessage != null) ...<Widget>[
          const SizedBox(height: 20),
          _ErrorPill(message: widget.errorMessage!, theme: theme),
        ],
      ],
    );
  }
}

// ── WIDGETS PRIVADOS ────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.surfaceLine)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('o',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted)),
        ),
        const Expanded(child: Divider(color: AppColors.surfaceLine)),
      ],
    );
  }
}

/// Campo de teléfono con selector de prefijo a la izquierda.
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.dialCode,
    required this.countryCode,
    required this.onCountryChanged,
    required this.enabled,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String dialCode;
  final String countryCode;
  final ValueChanged<CountryCode> onCountryChanged;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Selector de país (diálogo oscuro).
          CountryCodePicker(
            onChanged: onCountryChanged,
            initialSelection: countryCode,
            favorite: const <String>['+34', '+1', '+52', '+57', '+54'],
            showCountryOnly: false,
            showOnlyCountryWhenClosed: false,
            alignLeft: false,
            enabled: enabled,
            padding: EdgeInsets.zero,
            flagWidth: 26,
            textStyle: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            // --- Estilo del diálogo (antes salía en blanco) ---
            dialogBackgroundColor: AppColors.surface,
            barrierColor: Colors.black.withValues(alpha: 0.6),
            closeIcon:
                const Icon(Icons.close_rounded, color: AppColors.textSecondary),
            boxDecoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.surfaceLine),
            ),
            dialogItemPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            dialogTextStyle: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            searchStyle: const TextStyle(color: AppColors.textPrimary),
            searchDecoration: InputDecoration(
              hintText: 'Buscar país...',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceHigh,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.surfaceLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.attraRed),
              ),
            ),
          ),
          // Separador vertical.
          Container(
            width: 1,
            height: 28,
            color: AppColors.surfaceLine,
          ),
          // Campo de número.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: onSubmitted,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-]')),
                ],
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: '600 111 222',
                  hintStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra el número enviado (solo lectura) con botón "cambiar".
class _PhoneReadonly extends StatelessWidget {
  const _PhoneReadonly({required this.phone, required this.onEdit});
  final String phone;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.phone_rounded,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phone,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: const Text(
              'Cambiar',
              style: TextStyle(
                color: AppColors.attraRed,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo para el código SMS: grande, centrado, tipografía monoespaciada.
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
      onSubmitted: onSubmitted,
      autofocus: true,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 10,
      ),
      decoration: InputDecoration(
        hintText: '------',
        hintStyle: TextStyle(
          color: AppColors.textMuted.withValues(alpha: 0.5),
          fontSize: 28,
          letterSpacing: 10,
        ),
        labelText: 'Código SMS',
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon:
            const Icon(Icons.lock_outline_rounded, color: AppColors.attraRed),
      ),
    );
  }
}

/// Pill de error.
class _ErrorPill extends StatelessWidget {
  const _ErrorPill({required this.message, required this.theme});
  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.attraRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              color: AppColors.coral, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Botón social (pill claro) sobre fondo oscuro.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: AppColors.black),
                )
              else ...<Widget>[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.black,
                  ),
                  child: const Text('G',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
