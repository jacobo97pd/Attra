import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Longitud fija del PIN de la app.
const int kPinLength = 4;

/// Indicador de puntos del PIN (rellenos según dígitos introducidos).
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final Color on = error ? AppColors.danger : AppColors.attraRed;
    final Color off = context.colors.surfaceLine;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(kPinLength, (int i) {
        final bool active = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? on : Colors.transparent,
            border: Border.all(color: active ? on : off, width: 2),
          ),
        );
      }),
    );
  }
}

/// Teclado numérico para introducir el PIN. Notifica cada dígito y el borrado.
/// Opcionalmente muestra un botón de biometría en la esquina inferior izquierda.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final List<String> row in const <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final String d in row) _key(context, d),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _action(
              context,
              child: onBiometric == null
                  ? const SizedBox.shrink()
                  : Icon(Icons.fingerprint_rounded,
                      size: 30, color: context.colors.textSecondary),
              onTap: onBiometric,
            ),
            _key(context, '0'),
            _action(
              context,
              child: Icon(Icons.backspace_outlined,
                  size: 24, color: context.colors.textSecondary),
              onTap: onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(BuildContext context, String digit) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 76,
        height: 76,
        child: Material(
          color: context.colors.surfaceHigh,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onDigit(digit),
            child: Center(
              child: Text(
                digit,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context,
      {required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 76,
        height: 76,
        child: InkResponse(
          radius: 40,
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}
