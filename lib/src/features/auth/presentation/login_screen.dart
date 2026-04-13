import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
  final ValueChanged<String> onSendPhoneCode;
  final ValueChanged<String> onVerifyPhoneCode;
  final bool phoneCodeSent;
  final bool isLoading;
  final String? errorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _phoneController;
  late final TextEditingController _smsCodeController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _smsCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAppleButton = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Attra',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conecta con personas que van en serio.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: widget.isLoading ? null : widget.onGooglePressed,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.g_mobiledata_rounded, size: 22),
                    label: Text(
                      widget.isLoading
                          ? 'Iniciando sesion...'
                          : 'Continuar con Google',
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  if (showAppleButton) ...<Widget>[
                    const SizedBox(height: 12),
                    IgnorePointer(
                      ignoring: widget.isLoading,
                      child: Opacity(
                        opacity: widget.isLoading ? 0.55 : 1,
                        child: SignInWithAppleButton(
                          onPressed: widget.onApplePressed,
                          style: SignInWithAppleButtonStyle.black,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(12)),
                          text: 'Continuar con Apple',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'o',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    enabled: !widget.isLoading,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Telefono',
                      hintText: '+34600111222',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: widget.isLoading
                        ? null
                        : () => widget
                            .onSendPhoneCode(_phoneController.text.trim()),
                    child: Text(
                      widget.phoneCodeSent
                          ? 'Reenviar codigo SMS'
                          : 'Continuar con Telefono',
                    ),
                  ),
                  if (widget.phoneCodeSent) ...<Widget>[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _smsCodeController,
                      keyboardType: TextInputType.number,
                      enabled: !widget.isLoading,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Codigo SMS',
                        hintText: '123456',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: widget.isLoading
                          ? null
                          : () => widget.onVerifyPhoneCode(
                                _smsCodeController.text.trim(),
                              ),
                      child: const Text('Verificar codigo'),
                    ),
                  ],
                  if (widget.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      widget.errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
