import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../security/app_lock_controller.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import 'pin_pad.dart';

/// Pantalla de BLOQUEO (gate): pide el PIN para entrar. Si la biometría está
/// activada, la lanza automáticamente al abrirse. Al acertar, el
/// [AppLockController] desbloquea y el gate la oculta solo.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});

  final AppLockController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    await widget.controller.authenticateBiometric();
    // Si autentica, el controller pasa a desbloqueado y el gate quita esta
    // pantalla. Si falla, el usuario sigue con el PIN.
  }

  Future<void> _onDigit(String d) async {
    if (_entry.length >= kPinLength) return;
    setState(() {
      _error = false;
      _entry += d;
    });
    if (_entry.length == kPinLength) {
      final bool ok = await widget.controller.verifyPin(_entry);
      if (!ok && mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = true;
          _entry = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() {
      _error = false;
      _entry = _entry.substring(0, _entry.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const Spacer(flex: 2),
              const Icon(Icons.lock_rounded,
                  size: 44, color: AppColors.attraRed),
              const SizedBox(height: 18),
              Text(
                _error ? 'PIN incorrecto' : 'Introduce tu PIN',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _error
                          ? AppColors.danger
                          : context.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 24),
              PinDots(filled: _entry.length, error: _error),
              const Spacer(flex: 2),
              PinPad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                onBiometric:
                    widget.controller.biometricEnabled ? _tryBiometric : null,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla genérica para INTRODUCIR un PIN (configurar o confirmar). Devuelve
/// el PIN por [Navigator.pop] al completar los [kPinLength] dígitos.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({
    super.key,
    required this.title,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  String _entry = '';

  void _onDigit(String d) {
    if (_entry.length >= kPinLength) return;
    setState(() => _entry += d);
    if (_entry.length == kPinLength) {
      final String pin = _entry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(pin);
      });
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (widget.subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            PinDots(filled: _entry.length),
            const Spacer(),
            PinPad(onDigit: _onDigit, onBackspace: _onBackspace),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Flujo de CONFIGURACIÓN del PIN: pide el PIN y luego su confirmación.
/// Devuelve true si se configuró correctamente.
Future<bool> runAppLockSetup(
    BuildContext context, AppLockController controller) async {
  final String? first = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const PinEntryScreen(
        title: 'Crea un PIN',
        subtitle: 'Lo pedirás para abrir Attra.',
      ),
    ),
  );
  if (first == null) return false;
  if (!context.mounted) return false;

  final String? second = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const PinEntryScreen(
        title: 'Repite el PIN',
        subtitle: 'Confírmalo para asegurarnos de que lo recuerdas.',
      ),
    ),
  );
  if (second == null) return false;

  if (first != second) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Los PIN no coinciden. Inténtalo de nuevo.')),
      );
    }
    return false;
  }
  await controller.setPin(first);
  return true;
}

/// Pide el PIN actual (para confirmar una acción sensible: desactivar el
/// bloqueo). Devuelve true si el PIN es correcto.
Future<bool> confirmAppLockPin(
    BuildContext context, AppLockController controller) async {
  final String? pin = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const PinEntryScreen(
        title: 'Introduce tu PIN',
        subtitle: 'Confirma tu PIN para continuar.',
      ),
    ),
  );
  if (pin == null) return false;
  return controller.verifyPin(pin);
}
