import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Bloqueo de la app con PIN (+ biometría opcional). El estado REAL vive en el
/// almacenamiento seguro del dispositivo (no en Firestore): así el bloqueo
/// protege la app aunque no haya sesión y no se pueda eludir borrando datos de
/// la nube. La clave `security.appLock`/`security.biometricUnlock` de Ajustes es
/// solo un espejo para la UI.
///
/// El PIN nunca se guarda en claro: se almacena `sha256(salt + pin)` + el salt.
class AppLockController extends ChangeNotifier {
  AppLockController({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  /// Singleton (lo leen app.dart y Ajustes, sin inyección de dependencias).
  static final AppLockController instance = AppLockController();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  static const String _kHash = 'applock_pin_hash';
  static const String _kSalt = 'applock_pin_salt';
  static const String _kEnabled = 'applock_enabled';
  static const String _kBiometric = 'applock_biometric';

  bool _enabled = false;
  bool _biometricEnabled = false;
  bool _locked = false;
  bool _loaded = false;

  /// PIN activado.
  bool get enabled => _enabled;

  /// Biometría activada (requiere [enabled]).
  bool get biometricEnabled => _biometricEnabled;

  /// La app está bloqueada AHORA (debe mostrarse la pantalla de bloqueo).
  bool get isLocked => _enabled && _locked;

  bool get isLoaded => _loaded;

  /// Lee el estado del almacenamiento seguro al arrancar. Si el PIN está
  /// activado, la app arranca BLOQUEADA.
  Future<void> load() async {
    try {
      _enabled = (await _storage.read(key: _kEnabled)) == '1';
      _biometricEnabled = (await _storage.read(key: _kBiometric)) == '1';
    } catch (_) {
      _enabled = false;
      _biometricEnabled = false;
    }
    _locked = _enabled;
    _loaded = true;
    notifyListeners();
  }

  /// Bloquea la app (al pasar a segundo plano si el PIN está activo).
  void lock() {
    if (!_enabled) return;
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Desbloquea (tras PIN/biometría correctos).
  void _unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  // --- PIN ------------------------------------------------------------------

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt::$pin')).toString();

  String _newSalt() {
    final Random rng = Random.secure();
    final List<int> bytes =
        List<int>.generate(16, (_) => rng.nextInt(256), growable: false);
    return base64Url.encode(bytes);
  }

  /// Define (o cambia) el PIN y activa el bloqueo.
  Future<void> setPin(String pin) async {
    final String salt = _newSalt();
    await _storage.write(key: _kSalt, value: salt);
    await _storage.write(key: _kHash, value: _hash(pin, salt));
    await _storage.write(key: _kEnabled, value: '1');
    _enabled = true;
    _locked = false; // recién configurado: queda desbloqueado.
    notifyListeners();
  }

  /// Comprueba el PIN; si es correcto, desbloquea.
  Future<bool> verifyPin(String pin) async {
    try {
      final String? salt = await _storage.read(key: _kSalt);
      final String? hash = await _storage.read(key: _kHash);
      if (salt == null || hash == null) return false;
      final bool ok = _hash(pin, salt) == hash;
      if (ok) _unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Desactiva el bloqueo y borra el PIN guardado.
  Future<void> disable() async {
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kEnabled);
    await _storage.delete(key: _kBiometric);
    _enabled = false;
    _biometricEnabled = false;
    _locked = false;
    notifyListeners();
  }

  // --- Biometría ------------------------------------------------------------

  /// El dispositivo tiene biometría configurada y disponible.
  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;
      final List<BiometricType> types =
          await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Activa/desactiva la biometría (requiere PIN ya configurado).
  Future<void> setBiometricEnabled(bool value) async {
    if (value && !_enabled) return;
    await _storage.write(key: _kBiometric, value: value ? '1' : '0');
    _biometricEnabled = value;
    notifyListeners();
  }

  /// Lanza el prompt biométrico del SO. Si autentica, desbloquea.
  Future<bool> authenticateBiometric() async {
    try {
      final bool ok = await _localAuth.authenticate(
        localizedReason: 'Desbloquea Attra',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) _unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }
}
