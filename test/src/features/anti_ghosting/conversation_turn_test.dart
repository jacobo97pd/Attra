import 'package:attra/src/features/anti_ghosting/domain/anti_ghosting_config.dart';
import 'package:attra/src/features/anti_ghosting/domain/conversation_turn.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

const String userA = 'userA';
const String userB = 'userB';

Chat buildChat({
  required ChatStatus status,
  String? lastSender,
  MessageType? lastType = MessageType.text,
  DateTime? lastAt,
}) {
  return Chat(
    id: 'm1',
    matchId: 'm1',
    users: const <String>[userA, userB],
    status: status,
    unreadCountByUser: const <String, int>{},
    typingByUser: const <String, bool>{},
    lastMessageSenderId: lastSender,
    lastMessageType: lastType,
    lastMessageAt: lastAt,
  );
}

void main() {
  final DateTime t = DateTime(2026, 6, 30, 12);

  group('ConversationTurn (Attra Clear §1)', () {
    test('caso 1: si el último lo envió A, le toca a B', () {
      final Chat c = buildChat(
          status: ChatStatus.active, lastSender: userA, lastAt: t);
      final TurnInfo turn = c.turnFor(userA);
      expect(turn.waitingForUid, userB);
      expect(turn.isWaitingOn(userB), isTrue);
      expect(c.isMyTurn(userA), isFalse); // a A no le toca
    });

    test('caso 2: si el último lo envió B, le toca a A', () {
      final Chat c = buildChat(
          status: ChatStatus.active, lastSender: userB, lastAt: t);
      final TurnInfo turn = c.turnFor(userA);
      expect(turn.waitingForUid, userA);
      expect(c.isMyTurn(userA), isTrue);
      expect(turn.waitingSince, t);
    });

    test('caso 3: chat cerrado no cuenta como pendiente', () {
      final Chat c = buildChat(
          status: ChatStatus.closed, lastSender: userB, lastAt: t);
      expect(c.turnFor(userA).hasPendingTurn, isFalse);
      expect(c.isMyTurn(userA), isFalse);
    });

    test('caso 4: chat bloqueado no cuenta como ghosting', () {
      final Chat c = buildChat(
          status: ChatStatus.blocked, lastSender: userB, lastAt: t);
      expect(c.turnFor(userA).hasPendingTurn, isFalse);
    });

    test('mensaje de sistema no abre turno', () {
      final Chat c = buildChat(
          status: ChatStatus.active,
          lastSender: userB,
          lastType: MessageType.system,
          lastAt: t);
      expect(c.turnFor(userA).hasPendingTurn, isFalse);
    });

    test('contexto de apertura (like/attra) no abre turno', () {
      final Chat c = buildChat(
          status: ChatStatus.active,
          lastSender: userB,
          lastType: MessageType.likeContext,
          lastAt: t);
      expect(c.turnFor(userA).hasPendingTurn, isFalse);
    });

    test('sin último mensaje no hay turno', () {
      final Chat c = buildChat(status: ChatStatus.active, lastSender: null);
      expect(c.turnFor(userA).hasPendingTurn, isFalse);
    });

    test('waitedFor calcula la espera respecto a now', () {
      final Chat c = buildChat(
          status: ChatStatus.active, lastSender: userB, lastAt: t);
      final Duration? d =
          c.turnFor(userA).waitedFor(t.add(const Duration(hours: 18)));
      expect(d, const Duration(hours: 18));
    });
  });

  group('formatWaiting', () {
    test('minutos / horas / días', () {
      expect(formatWaiting(const Duration(minutes: 30)), 'hace 30 min');
      expect(formatWaiting(const Duration(hours: 18)), 'hace 18 h');
      expect(formatWaiting(const Duration(days: 1)), 'hace 1 día');
      expect(formatWaiting(const Duration(days: 3)), 'hace 3 días');
      expect(formatWaiting(const Duration(seconds: 5)), 'ahora mismo');
    });
  });

  group('AntiGhostingConfig (§14 fallback defensivo)', () {
    test('mapa nulo/vacío cae a defaults seguros', () {
      final AntiGhostingConfig c = AntiGhostingConfig.fromMap(null);
      expect(c.enabled, isTrue); // core no destructivo on
      expect(c.pendingLimitEnabled, isFalse); // bloqueo off por defecto
      expect(c.pendingLimitFree, 5);
      expect(c.pendingLimitPlus, 8);
      expect(c.pendingLimitPro, 10);
      expect(c.pendingMaxAgeHours, 24);
    });

    test('lee overrides de Remote Config (snake_case)', () {
      final AntiGhostingConfig c = AntiGhostingConfig.fromMap(<String, dynamic>{
        'anti_ghosting_enabled': false,
        'anti_ghosting_pending_limit_enabled': true,
        'anti_ghosting_pending_limit_free': 3,
      });
      expect(c.enabled, isFalse);
      expect(c.pendingLimitEnabled, isTrue);
      expect(c.pendingLimitFree, 3);
    });

    test('límite por plan', () {
      const AntiGhostingConfig c = AntiGhostingConfig.safeDefaults;
      expect(c.pendingLimitForPlan(isPlus: false, isPro: false), 5);
      expect(c.pendingLimitForPlan(isPlus: true, isPro: false), 8);
      expect(c.pendingLimitForPlan(isPlus: false, isPro: true), 10);
    });
  });
}
