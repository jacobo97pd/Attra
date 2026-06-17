import 'package:flutter_test/flutter_test.dart';

import 'dart:math';

import 'package:attra/src/features/match/domain/date_builder.dart';
import 'package:attra/src/features/match/domain/match_journey.dart';
import 'package:attra/src/features/match/domain/match_journey_gating.dart';
import 'package:attra/src/features/match/presentation/icebreaker_sheet.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';

void main() {
  group('MatchJourneyStatus parse', () {
    test('fromValue tolera snake_case, camelCase y desconocidos', () {
      expect(MatchJourneyStatus.fromValue('conversation_active'),
          MatchJourneyStatus.conversationActive);
      expect(MatchJourneyStatus.fromValue('dateProposed'),
          MatchJourneyStatus.dateProposed);
      expect(MatchJourneyStatus.fromValue('???'), MatchJourneyStatus.newMatch);
    });
  });

  group('MatchJourney.fromMap (fallback matches antiguos)', () {
    test('sin journeyStatus usa el fallback derivado', () {
      final MatchJourney j = MatchJourney.fromMap(
        <String, dynamic>{},
        fallback: MatchJourneyStatus.conversationActive,
      );
      expect(j.status, MatchJourneyStatus.conversationActive);
    });

    test('con journeyStatus persistido lo respeta', () {
      final MatchJourney j = MatchJourney.fromMap(
        <String, dynamic>{'journeyStatus': 'date_accepted'},
        fallback: MatchJourneyStatus.newMatch,
      );
      expect(j.status, MatchJourneyStatus.dateAccepted);
    });
  });

  group('MatchJourney.derive', () {
    test('match nuevo sin mensajes', () {
      final MatchJourney j = MatchJourney.derive(realMessageCount: 0);
      expect(j.status, MatchJourneyStatus.newMatch);
      expect(j.suggestedCta, MatchJourneyCta.launchIcebreaker);
    });

    test('pocos mensajes sin juego => rompiendo el hielo', () {
      final MatchJourney j = MatchJourney.derive(realMessageCount: 3);
      expect(j.status, MatchJourneyStatus.icebreakerSuggested);
      expect(j.suggestedCta, MatchJourneyCta.launchIcebreaker);
    });

    test('juego completado pesa más que pocos mensajes', () {
      final MatchJourney j = MatchJourney.derive(
          realMessageCount: 2, hasCompletedGame: true);
      expect(j.status, MatchJourneyStatus.gameCompleted);
      expect(j.suggestedCta, MatchJourneyCta.proposePlan);
    });

    test('>=6 mensajes => conversación activa => CTA proponer plan', () {
      final MatchJourney j = MatchJourney.derive(realMessageCount: 8);
      expect(j.status, MatchJourneyStatus.conversationActive);
      expect(j.suggestedCta, MatchJourneyCta.proposePlan);
    });

    test('cita propuesta y aceptada tienen prioridad', () {
      expect(
        MatchJourney.derive(
                realMessageCount: 20, dateProposalStatus: 'pending')
            .status,
        MatchJourneyStatus.dateProposed,
      );
      expect(
        MatchJourney.derive(
                realMessageCount: 20, dateProposalStatus: 'accepted')
            .status,
        MatchJourneyStatus.dateAccepted,
      );
    });
  });

  group('Enfriándose (Fase 9)', () {
    final DateTime now = DateTime(2026, 6, 17, 12);
    test('conversación parada >48h se enfría', () {
      final MatchJourney j = MatchJourney.derive(
        realMessageCount: 3,
        lastActivityAt: now.subtract(const Duration(hours: 60)),
        now: now,
      );
      expect(j.coolingDown, isTrue);
      expect(j.suggestedCta, MatchJourneyCta.reactivate);
    });

    test('actividad reciente no se enfría', () {
      final MatchJourney j = MatchJourney.derive(
        realMessageCount: 3,
        lastActivityAt: now.subtract(const Duration(hours: 2)),
        now: now,
      );
      expect(j.coolingDown, isFalse);
    });

    test('cita aceptada nunca se marca como enfriándose', () {
      final MatchJourney j = MatchJourney.derive(
        realMessageCount: 10,
        dateProposalStatus: 'accepted',
        lastActivityAt: now.subtract(const Duration(days: 10)),
        now: now,
      );
      expect(j.coolingDown, isFalse);
    });
  });

  group('Feature flags Match Journey (Fase 12)', () {
    test('por defecto todos desactivados (app igual que antes)', () {
      const MonetizationFeatureFlags f = MonetizationFeatureFlags();
      expect(f.matchJourneyEnabled, isFalse);
      expect(f.icebreakersEnabled, isFalse);
      expect(f.miniGamesEnabled, isFalse);
      expect(f.dateBuilderEnabled, isFalse);
      expect(f.matchReactivationEnabled, isFalse);
    });

    test('lee snake_case desde config', () {
      final MonetizationFeatureFlags f =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'match_journey_enabled': true,
        'icebreakers_enabled': true,
        'date_builder_enabled': true,
      });
      expect(f.matchJourneyEnabled, isTrue);
      expect(f.icebreakersEnabled, isTrue);
      expect(f.dateBuilderEnabled, isTrue);
      expect(f.twoTruthsEnabled, isFalse);
    });
  });

  group('Icebreakers (Fase 3)', () {
    test('pools no vacíos', () {
      expect(IcebreakerCatalog.quickQuestions, isNotEmpty);
      expect(IcebreakerCatalog.thisOrThat, isNotEmpty);
      expect(IcebreakerCatalog.twoTruthsTemplate, contains('mentira'));
    });

    test('random devuelve un elemento válido del pool', () {
      final Random rng = Random(42);
      final String q = IcebreakerCatalog.randomQuick(rng);
      expect(IcebreakerCatalog.quickQuestions, contains(q));
      final String t = IcebreakerCatalog.randomThisOrThat(rng);
      expect(IcebreakerCatalog.thisOrThat, contains(t));
    });
  });

  group('Date Builder (Fase 7)', () {
    test('isComplete solo con los 5 campos', () {
      const DatePreferences empty = DatePreferences();
      expect(empty.isComplete, isFalse);
      final DatePreferences full = empty.copyWith(
        planType: PlanType.cafe,
        moment: DateMoment.tarde,
        budget: DateBudget.barato,
        duration: DateDuration.h1,
        vibe: DateVibe.casual,
      );
      expect(full.isComplete, isTrue);
    });

    test('suggest compone lugar + nota + resumen coherentes', () {
      final DatePlanSuggestion s = DateBuilder.suggest(const DatePreferences(
        planType: PlanType.cafe,
        moment: DateMoment.tarde,
        budget: DateBudget.barato,
        duration: DateDuration.h1,
        vibe: DateVibe.tranquilo,
      ));
      expect(s.placeName, isNotEmpty);
      expect(s.note.toLowerCase(), contains('café'));
      expect(s.summary.toLowerCase(), contains('tranquilo'));
    });

    test('suggest no rompe con preferencias vacías (defaults suaves)', () {
      final DatePlanSuggestion s = DateBuilder.suggest(const DatePreferences());
      expect(s.placeName, isNotEmpty);
      expect(s.summary, isNotEmpty);
    });
  });

  group('Gating Free/Plus/Pro (Fase 10)', () {
    test('Free es limitado; Pro ilimitado + IA coach', () {
      final JourneyLimits free =
          MatchJourneyPolicy.forTier(SubscriptionTier.free);
      expect(free.dateBuilderFull, isFalse);
      expect(free.canReactivate, isFalse);
      expect(free.aiCoach, isFalse);
      expect(free.unlimitedIcebreakers, isFalse);

      final JourneyLimits pro =
          MatchJourneyPolicy.forTier(SubscriptionTier.pro);
      expect(pro.unlimitedIcebreakers, isTrue);
      expect(pro.canReactivate, isTrue);
      expect(pro.aiCoach, isTrue);
    });

    test('Plus desbloquea Date Builder completo y reactivar, sin IA coach', () {
      final JourneyLimits plus =
          MatchJourneyPolicy.forTier(SubscriptionTier.plus);
      expect(plus.dateBuilderFull, isTrue);
      expect(plus.canReactivate, isTrue);
      expect(plus.aiCoach, isFalse);
      // premium se trata como plus.
      expect(MatchJourneyPolicy.forTier(SubscriptionTier.premium).canReactivate,
          isTrue);
    });

    test('overrides de config respetan defaults seguros si falta la clave', () {
      final JourneyLimits l = MatchJourneyPolicy.forTierWithOverrides(
        SubscriptionTier.free,
        <String, dynamic>{'dailyIcebreakers': 5},
      );
      expect(l.dailyIcebreakers, 5);
      expect(l.canReactivate, isFalse); // no se desbloquea Pro sin entitlement
    });
  });
}
