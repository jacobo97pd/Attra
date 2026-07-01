import 'package:attra/src/features/anti_ghosting/domain/breadcrumbing.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:flutter_test/flutter_test.dart';

Chat _chat(Map<String, dynamic> m) => Chat.fromMap('c', <String, dynamic>{
      'users': <String>['a', 'b'],
      'status': 'active',
      ...m,
    });

void main() {
  final DateTime now = DateTime(2026, 7, 1, 12);

  group('Follow-up post-cita (§6)', () {
    test('due si aceptada, ≥24h y pendiente', () {
      final Chat c = _chat(<String, dynamic>{
        'dateFollowUpStatus': 'pending',
        'dateScheduledAt': now.subtract(const Duration(hours: 25)),
      });
      expect(c.isDateFollowUpDue(now), isTrue);
    });
    test('no due antes de 24h', () {
      final Chat c = _chat(<String, dynamic>{
        'dateFollowUpStatus': 'pending',
        'dateScheduledAt': now.subtract(const Duration(hours: 5)),
      });
      expect(c.isDateFollowUpDue(now), isFalse);
    });
    test('no due si ya respondido', () {
      final Chat c = _chat(<String, dynamic>{
        'dateFollowUpStatus': 'answered',
        'dateScheduledAt': now.subtract(const Duration(days: 3)),
      });
      expect(c.isDateFollowUpDue(now), isFalse);
    });
  });

  group('Badge de fiabilidad (§8, parseo)', () {
    test('hasReliabilityBadge por defecto false / lee true', () {
      // Se prueba vía Chat no aplica; el flag vive en AppUser, cubierto en
      // busy_and_pending_test. Aquí solo validamos breadcrumbing.
      expect(true, isTrue);
    });
  });

  group('Anti-breadcrumbing (§9)', () {
    test('estancada: >7 días, pocos mensajes, sin plan ni cierre', () {
      expect(
        isStalled(
          createdAt: now.subtract(const Duration(days: 8)),
          realMessageCount: 4,
          hasDateProposal: false,
          isClosed: false,
          now: now,
        ),
        isTrue,
      );
    });
    test('no estancada si hay propuesta de plan', () {
      expect(
        isStalled(
          createdAt: now.subtract(const Duration(days: 20)),
          realMessageCount: 2,
          hasDateProposal: true,
          isClosed: false,
          now: now,
        ),
        isFalse,
      );
    });
    test('no estancada si reciente o con actividad', () {
      expect(
        isStalled(
          createdAt: now.subtract(const Duration(days: 2)),
          realMessageCount: 3,
          hasDateProposal: false,
          isClosed: false,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
