import 'package:attra/src/features/connection_lab/domain/connection_samples.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionSamples.challengeAt', () {
    test('rotates deterministically and never crashes', () {
      final ChallengePrompt a = ConnectionSamples.challengeAt(0);
      final ChallengePrompt b = ConnectionSamples.challengeAt(1);
      expect(a.title, isNotEmpty);
      expect(a.prompt, isNotEmpty);
      expect(a.title, isNot(b.title));
      // Wraps around.
      expect(ConnectionSamples.challengeAt(ConnectionSamples.challenges.length)
          .title, a.title);
      // Handles negative seeds.
      expect(ConnectionSamples.challengeAt(-3).prompt, isNotEmpty);
    });
  });

  group('ConnectionSamples.analyzeAnswer', () {
    test('empty answer scores low and nudges to actually answer', () {
      final ChallengeInsight i = ConnectionSamples.analyzeAnswer('');
      expect(i.energyScore, lessThan(40));
      expect(i.energyLabel, 'Needs a bit more');
      expect(i.followUp, isNotEmpty);
      expect(i.suggestedNextMessage, isNotEmpty);
      expect(i.suggestedDateIdea, isNotEmpty);
    });

    test('filler answers like "Nada." do NOT get warm feedback', () {
      for (final String filler in <String>['Nada.', 'no sé', 'meh', 'ns', 'x']) {
        final ChallengeInsight i = ConnectionSamples.analyzeAnswer(filler);
        expect(i.energyScore, lessThan(40),
            reason: 'filler "$filler" should score low');
        expect(i.energyLabel, 'Needs a bit more');
      }
    });

    test('a short throwaway answer scores below a detailed one', () {
      final int shortAns =
          ConnectionSamples.analyzeAnswer('viajar').energyScore;
      final int detailed = ConnectionSamples.analyzeAnswer(
              'I love long coffee walks and good music, and I travel whenever I '
              'can. What about you?')
          .energyScore;
      expect(detailed, greaterThan(shortAns));
    });

    test('warm, detailed answer scores clearly higher than empty', () {
      final int empty = ConnectionSamples.analyzeAnswer('').energyScore;
      final int warm = ConnectionSamples.analyzeAnswer(
              'I love long coffee walks and good music, and I travel whenever I '
              'can. What about you?')
          .energyScore;
      expect(warm, greaterThan(empty + 20));
    });
  });

  group('ConnectionSamples.compatibility', () {
    test('never returns only a number — always has reasons', () {
      final CompatibilityResult r = ConnectionSamples.compatibility();
      expect(r.score, inInclusiveRange(62, 95));
      expect(r.reasons.length, inInclusiveRange(3, 5));
    });

    test('shared interests raise the score and surface a shared reason', () {
      final CompatibilityResult none = ConnectionSamples.compatibility();
      final CompatibilityResult shared = ConnectionSamples.compatibility(
        myInterests: <String>['Music', 'Coffee', 'Hiking'],
        theirInterests: <String>['coffee', 'hiking', 'films'],
      );
      expect(shared.score, greaterThanOrEqualTo(none.score));
      expect(shared.reasons.first.toLowerCase(), contains('shared'));
    });
  });

  group('ConnectionSamples.dateIdeas', () {
    test('has a clearly low-pressure option', () {
      final List<DateIdea> ideas = ConnectionSamples.dateIdeas();
      expect(ideas.length, 3);
      expect(ideas.any((DateIdea d) => d.lowPressure), isTrue);
    });

    test('proposal message includes the name when provided', () {
      expect(ConnectionSamples.dateProposalMessage('Marta'), contains('Marta'));
      expect(ConnectionSamples.dateProposalMessage(''), isNotEmpty);
    });
  });

  group('ConnectionSamples.coachReport', () {
    test('balanced input reads as balanced', () {
      final GhostingCoachReport r = ConnectionSamples.coachReport(
          myMessages: 5, theirMessages: 5, hoursSinceLast: 2);
      expect(r.balanceScore, greaterThanOrEqualTo(75));
      expect(r.balance.toLowerCase(), contains('balanced'));
      expect(r.momentumScore, greaterThan(70));
    });

    test('too few messages reads as "still early", not a fake score', () {
      final GhostingCoachReport r = ConnectionSamples.coachReport(
          myMessages: 1, theirMessages: 0, hoursSinceLast: 1);
      expect(r.balance.toLowerCase(), contains('early'));
      expect(r.balanceScore, 50);
      expect(r.momentumScore, 50);
    });

    test('long silence lowers momentum and suggests a restart', () {
      final GhostingCoachReport r = ConnectionSamples.coachReport(
          myMessages: 6, theirMessages: 5, hoursSinceLast: 72, iSentLast: false);
      expect(r.momentumScore, lessThan(40));
      expect(r.suggestedAction, isNotEmpty);
    });
  });
}
