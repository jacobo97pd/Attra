import 'package:attra/src/features/anti_ghosting/data/pending_conversations_controller.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser buildUser({
  required bool busyEnabled,
  DateTime? busyUntil,
}) {
  return AppUser(
    uid: 'u1',
    email: null,
    displayName: 'U',
    photoUrl: null,
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    busyModeEnabled: busyEnabled,
    busyModeUntil: busyUntil,
  );
}

void main() {
  group('Modo ocupado (Attra Clear §4, expiración defensiva)', () {
    test('activo si enabled y la fecha está en el futuro', () {
      final AppUser u = buildUser(
        busyEnabled: true,
        busyUntil: DateTime.now().add(const Duration(days: 2)),
      );
      expect(u.busyModeActive, isTrue);
      expect(u.busyModeUntilOrNull, isNotNull);
    });

    test('expiración defensiva: fecha pasada => inactivo aunque enabled=true', () {
      final AppUser u = buildUser(
        busyEnabled: true,
        busyUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(u.busyModeActive, isFalse);
      expect(u.busyModeUntilOrNull, isNull);
    });

    test('enabled=false => inactivo', () {
      final AppUser u = buildUser(
        busyEnabled: false,
        busyUntil: DateTime.now().add(const Duration(days: 2)),
      );
      expect(u.busyModeActive, isFalse);
    });

    test('sin fecha => inactivo', () {
      final AppUser u = buildUser(busyEnabled: true);
      expect(u.busyModeActive, isFalse);
    });
  });

  group('Límite de pendientes (Attra Clear §2, conteo por edad)', () {
    final DateTime now = DateTime(2026, 7, 1, 12);

    test('solo cuenta las pendientes más antiguas que maxAgeHours', () {
      final List<DateTime> waiting = <DateTime>[
        now.subtract(const Duration(hours: 30)), // cuenta (>24h)
        now.subtract(const Duration(hours: 25)), // cuenta
        now.subtract(const Duration(hours: 2)), // NO (reciente)
        now.subtract(const Duration(hours: 26)), // cuenta
      ];
      expect(
        PendingConversationsController.countOlderThan(waiting, 24, now: now),
        3,
      );
    });

    test('chats recientes no activan el límite', () {
      final List<DateTime> waiting = <DateTime>[
        now.subtract(const Duration(hours: 1)),
        now.subtract(const Duration(hours: 5)),
      ];
      expect(
        PendingConversationsController.countOlderThan(waiting, 24, now: now),
        0,
      );
    });

    test('lista vacía => 0', () {
      expect(
        PendingConversationsController.countOlderThan(
            const <DateTime>[], 24, now: now),
        0,
      );
    });
  });
}
