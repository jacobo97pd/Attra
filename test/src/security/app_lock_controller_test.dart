import 'package:attra/src/security/app_lock_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifica el flujo de PIN del bloqueo de app contra un almacenamiento seguro
/// simulado en memoria (canal de flutter_secure_storage mockeado).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      final Map<dynamic, dynamic> args =
          (call.arguments as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
      final String? key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          store[key!] = args['value'] as String;
          return null;
        case 'read':
          return store[key];
        case 'delete':
          store.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setPin activa el bloqueo y guarda el PIN hasheado (no en claro)',
      () async {
    final AppLockController c = AppLockController();
    await c.setPin('1234');
    expect(c.enabled, true);
    // El PIN nunca se guarda en claro.
    expect(store.values.any((String v) => v.contains('1234')), false);
  });

  test('verifyPin acepta el correcto y rechaza el incorrecto', () async {
    final AppLockController c = AppLockController();
    await c.setPin('2468');
    expect(await c.verifyPin('0000'), false);
    expect(await c.verifyPin('2468'), true);
  });

  test('load arranca BLOQUEADO si el PIN estaba activo', () async {
    final AppLockController c1 = AppLockController();
    await c1.setPin('1111');
    // Nueva instancia (reinicio de app) leyendo el mismo almacenamiento.
    final AppLockController c2 = AppLockController();
    await c2.load();
    expect(c2.enabled, true);
    expect(c2.isLocked, true);
    expect(await c2.verifyPin('1111'), true);
    expect(c2.isLocked, false);
  });

  test('disable borra el PIN y desactiva el bloqueo', () async {
    final AppLockController c = AppLockController();
    await c.setPin('4321');
    await c.disable();
    expect(c.enabled, false);
    expect(c.isLocked, false);
    expect(store.isEmpty, true);
  });
}
