import 'package:attra/src/features/safedate/domain/conversation_risk.dart';
import 'package:attra/src/features/safedate/domain/post_date_review.dart';
import 'package:attra/src/features/safedate/domain/safe_date_alert.dart';
import 'package:attra/src/features/safedate/domain/safe_date_checkin.dart';
import 'package:attra/src/features/safedate/domain/safe_date_plan.dart';
import 'package:attra/src/features/safedate/domain/safedate_analytics.dart';
import 'package:attra/src/features/safedate/domain/safedate_flags.dart';
import 'package:attra/src/features/safedate/domain/trusted_contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafeDateFlags', () {
    test('defaults: todo OFF (fallback seguro)', () {
      const SafeDateFlags f = SafeDateFlags.disabled;
      expect(f.enabled, isFalse);
      expect(f.contactsActive, isFalse);
      expect(f.liveLocationActive, isFalse);
      expect(f.emergencyNumber, '112');
    });

    test('el master switch OFF desactiva todos los sub-features', () {
      final SafeDateFlags f = SafeDateFlags.fromMap(<String, dynamic>{
        'feature_safedate_enabled': false,
        'feature_safedate_trusted_contacts_enabled': true,
        'feature_safedate_checkins_enabled': true,
      });
      expect(f.contactsActive, isFalse);
      expect(f.checkinsActive, isFalse);
    });

    test('master ON + sub ON → activo; tiempos configurables', () {
      final SafeDateFlags f = SafeDateFlags.fromMap(<String, dynamic>{
        'feature_safedate_enabled': true,
        'feature_safedate_trusted_contacts_enabled': true,
        'safedate_checkin_missed_threshold_minutes': 40,
      });
      expect(f.enabled, isTrue);
      expect(f.contactsActive, isTrue);
      expect(f.datePlanActive, isFalse); // su flag sigue OFF
      expect(f.checkinMissedThresholdMinutes, 40);
    });
  });

  group('TrustedContactInput.validate', () {
    test('exige nombre y al menos un canal', () {
      expect(const TrustedContactInput(displayName: '').validate(), isNotNull);
      expect(
          const TrustedContactInput(displayName: 'Ana').validate(), isNotNull);
      expect(
          const TrustedContactInput(displayName: 'Ana', phone: '600123123')
              .validate(),
          isNull);
    });

    test('normaliza teléfono y email', () {
      final TrustedContactInput n = const TrustedContactInput(
        displayName: '  Ana  ',
        phone: '+34 600-123 123',
        email: '  Ana@Mail.COM ',
      ).normalized();
      expect(n.displayName, 'Ana');
      expect(n.phone, '+34600123123'.replaceAll(' ', ''));
      expect(n.email, 'ana@mail.com');
    });

    test('rechaza email y teléfono inválidos', () {
      expect(
          const TrustedContactInput(displayName: 'Ana', email: 'noemail')
              .validate(),
          isNotNull);
      expect(
          const TrustedContactInput(displayName: 'Ana', phone: '123')
              .validate(),
          isNotNull);
    });
  });

  group('SafeDatePlan', () {
    test('return por defecto = scheduledAt + duración', () {
      final DateTime at = DateTime(2026, 7, 20, 19, 30);
      final SafeDatePlan p = SafeDatePlan.fromMap('p', <String, dynamic>{
        'ownerUserId': 'me',
        'matchId': 'm',
        'otherUserId': 'other',
        'placeName': 'Café X',
        'scheduledAt': at.toIso8601String(),
        'expectedDurationMinutes': 60,
        'status': 'scheduled',
      });
      expect(p.status.isOpen, isTrue);
      expect(p.effectiveReturnAt, at.add(const Duration(minutes: 60)));
    });
  });

  group('enums SafeDate', () {
    test('estados/alertas parsean y caen a defaults seguros', () {
      expect(SafeDatePlanStatus.fromValue('active'), SafeDatePlanStatus.active);
      expect(SafeDatePlanStatus.fromValue('xxx'), SafeDatePlanStatus.draft);
      expect(CheckInStatus.fromValue('need_help').needsAttention, isTrue);
      expect(SafeDateAlertType.fromValue('silent_alert').isSilent, isTrue);
      expect(SafeDateAlertType.fromValue('contact_me').isSilent, isFalse);
    });

    test(
        'CheckIn.fromMap lee las claves del backend (planId/ownerUserId/dueAt)',
        () {
      final DateTime due = DateTime.utc(2026, 7, 14, 20, 30);
      final SafeDateCheckIn c = SafeDateCheckIn.fromMap('c1', <String, dynamic>{
        'planId': 'plan-1',
        'ownerUserId': 'me',
        'type': 'expected_return',
        'status': 'pending',
        'dueAt': due.toIso8601String(),
        'reminderCount': 2,
      });
      expect(c.safeDatePlanId, 'plan-1');
      expect(c.userId, 'me');
      expect(c.type, CheckInType.expectedReturn);
      expect(c.status, CheckInStatus.pending);
      expect(c.scheduledAt.toUtc(), due);
      expect(c.reminderCount, 2);
    });

    test('Alert.fromMap lee alertType/severity del backend', () {
      final SafeDateAlert a = SafeDateAlert.fromMap('a1', <String, dynamic>{
        'safeDatePlanId': 'p1',
        'userId': 'me',
        'alertType': 'silent_alert',
        'severity': 'urgent',
      });
      expect(a.alertType, SafeDateAlertType.silentAlert);
      expect(a.alertType.isSilent, isTrue);
      expect(a.severity, SafeDateAlertSeverity.urgent);
    });

    test('ConversationRiskResult.fromMap parsea tier/categorías/consejos', () {
      final ConversationRiskResult r =
          ConversationRiskResult.fromMap(<String, dynamic>{
        'tier': 'warning',
        'categories': <String>['money_request'],
        'intro': 'Ojo',
        'tips': <String>['No envíes dinero'],
      });
      expect(r.tier, 'warning');
      expect(r.hasSignals, isTrue);
      expect(r.tips, contains('No envíes dinero'));
      // Sin señales → hasSignals false.
      expect(
          ConversationRiskResult.fromMap(
              <String, dynamic>{'tier': 'info', 'tips': <String>[]}).hasSignals,
          isFalse);
    });
  });

  group('PostDateSafetyReview', () {
    test('toCreateMap no incluye reviewerUserId ni notas en claro extra', () {
      const PostDateSafetyReview r = PostDateSafetyReview(
        id: '',
        safeDatePlanId: 'p',
        reviewerUserId: 'me',
        reviewedUserId: 'other',
        feltSafe: false,
        respectedBoundaries: false,
        matchedProfile: true,
        experiencedPressure: true,
        wantsToBlock: true,
        wantsToReport: true,
        concernCategories: <String>[PostDateConcern.sexualPressure],
      );
      final Map<String, dynamic> map = r.toCreateMap();
      expect(map['reviewedUserId'], 'other');
      expect(map.containsKey('reviewerUserId'), isFalse); // lo pone el backend
      expect(map['concernCategories'], contains('sexual_pressure'));
    });
  });

  group('SafeDateEvents.safeParams', () {
    test('filtra claves sensibles', () {
      final Map<String, Object> out =
          SafeDateEvents.safeParams(<String, Object>{
        'status': 'created',
        'phone': '600',
        'latitude': 40.4,
        'count': 2,
      });
      expect(out.containsKey('status'), isTrue);
      expect(out.containsKey('count'), isTrue);
      expect(out.containsKey('phone'), isFalse);
      expect(out.containsKey('latitude'), isFalse);
    });
  });
}
