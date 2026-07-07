import 'package:attra/src/features/date_plans/domain/date_plan.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatePlanProposal.fromMap', () {
    test('parsea campos, opciones y estado', () {
      final DatePlanProposal p = DatePlanProposal.fromMap('plan1', <String, dynamic>{
        'matchId': 'm1',
        'createdBy': 'a',
        'users': <String>['a', 'b'],
        'status': 'accepted_by_user_a',
        'source': 'ai_suggested',
        'city': 'Madrid',
        'zone': 'Chamberí',
        'privacyMode': 'zone',
        'acceptedBy': <String>['a'],
        'votesByUser': <String, dynamic>{'a': 'opt_1'},
        'commonInterests': <String>['café', 'arte'],
        'options': <dynamic>[
          <String, dynamic>{
            'id': 'opt_1',
            'title': 'Café tranquilo',
            'placeName': 'Café X',
            'placeId': 'gp_123',
            'rating': 4.5,
            'reviewCount': 820,
            'priceLevel': 2,
            'suggestedDateTime': '2026-07-09T19:30:00.000Z',
            'tags': <String>['relajado'],
          },
        ],
      });

      expect(p.matchId, 'm1');
      expect(p.status, DatePlanStatus.acceptedByUserA);
      expect(p.status.isOpen, isTrue);
      expect(p.source, DatePlanSource.aiSuggested);
      expect(p.privacyMode, DatePlanPrivacyMode.zone);
      expect(p.commonInterests, contains('arte'));
      expect(p.hasVoted('a'), isTrue);
      expect(p.hasVoted('b'), isFalse);
      expect(p.hasAccepted('a'), isTrue);
      expect(p.options.length, 1);

      final DatePlanOption o = p.options.first;
      expect(o.hasRealPlace, isTrue);
      expect(o.rating, 4.5);
      expect(o.reviewCount, 820);
      expect(o.suggestedDateTime, isNotNull);
    });

    test('valores desconocidos caen a defaults seguros', () {
      final DatePlanProposal p =
          DatePlanProposal.fromMap('x', <String, dynamic>{});
      expect(p.status, DatePlanStatus.pending);
      expect(p.source, DatePlanSource.manual);
      expect(p.privacyMode, DatePlanPrivacyMode.city);
      expect(p.options, isEmpty);
      expect(p.isActionable, isTrue); // pending, sin expiración
    });

    test('confirmada expone la opción elegida y no es accionable', () {
      final DatePlanProposal p =
          DatePlanProposal.fromMap('x', <String, dynamic>{
        'users': <String>['a', 'b'],
        'status': 'confirmed',
        'selectedOptionId': 'opt_2',
        'votesByUser': <String, dynamic>{'a': 'opt_2', 'b': 'opt_2'},
        'options': <dynamic>[
          <String, dynamic>{'id': 'opt_1', 'title': 'Café'},
          <String, dynamic>{'id': 'opt_2', 'title': 'Paseo', 'placeName': 'Retiro'},
        ],
      });
      expect(p.status.isConfirmed, isTrue);
      expect(p.status.isOpen, isFalse);
      expect(p.isActionable, isFalse);
      expect(p.selectedOption?.title, 'Paseo');
      expect(p.hasVoted('a'), isTrue);
      expect(p.hasVoted('b'), isTrue);
    });

    test('propuesta caducada no es accionable', () {
      final DatePlanProposal p =
          DatePlanProposal.fromMap('x', <String, dynamic>{
        'status': 'pending',
        'expiresAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });
      expect(p.isExpired, isTrue);
      expect(p.isActionable, isFalse);
    });
  });

  group('DatePlanOption', () {
    test('opción genérica (sin Places) no tiene lugar real', () {
      const DatePlanOption o = DatePlanOption(id: 'opt_1', title: 'Paseo');
      expect(o.hasRealPlace, isFalse);
    });

    test('toCreateMap omite geo exacta y campos nulos', () {
      const DatePlanOption o = DatePlanOption(
        id: 'opt_1',
        title: 'Café',
        placeName: 'Sitio',
      );
      final Map<String, dynamic> map = o.toCreateMap();
      expect(map.containsKey('latitude'), isFalse);
      expect(map.containsKey('longitude'), isFalse);
      expect(map.containsKey('rating'), isFalse); // null → omitido
      expect(map['title'], 'Café');
    });
  });

  group('MonetizationFeatureFlags — Attra Plans', () {
    test('defaults: apagado y no operativo', () {
      const MonetizationFeatureFlags f = MonetizationFeatureFlags();
      expect(f.datePlansEnabled, isFalse);
      expect(f.datePlansActive, isFalse);
      expect(f.datePlansFreeLimit, 1);
    });

    test('parsea snake_case y respeta el kill switch', () {
      final MonetizationFeatureFlags f =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'date_plans_enabled': true,
        'date_plans_ai_enabled': true,
        'date_plans_places_enabled': true,
        'date_plans_free_limit': 3,
      });
      expect(f.datePlansEnabled, isTrue);
      expect(f.datePlansAiEnabled, isTrue);
      expect(f.datePlansPlacesEnabled, isTrue);
      expect(f.datePlansFreeLimit, 3);
      expect(f.datePlansActive, isTrue);

      final MonetizationFeatureFlags killed =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'date_plans_enabled': true,
        'date_plans_kill_switch': true,
      });
      expect(killed.datePlansEnabled, isTrue);
      expect(killed.datePlansActive, isFalse); // kill switch manda
    });

    test('constructor disabled apaga Attra Plans', () {
      const MonetizationFeatureFlags f = MonetizationFeatureFlags.disabled();
      expect(f.datePlansActive, isFalse);
      expect(f.datePlansKillSwitch, isTrue);
    });
  });
}
