/// Deterministic, offline "AI" sample engine that powers the Connection Lab
/// experiences (Demo Challenge, Anti-Ghosting Coach, Compatibility Insights,
/// Date Planner). It never calls the network, so it always works — for new
/// users without matches and for reviewers. When the real AI backend is wired,
/// these functions can be swapped for live calls behind the same shapes.
///
/// Pure functions (no Flutter/Firebase) so they can be unit-tested.
library;

/// A single guided-conversation challenge prompt.
class ChallengePrompt {
  const ChallengePrompt({required this.title, required this.prompt});
  final String title;
  final String prompt;
}

/// Result of analysing an answer in the Demo Challenge.
class ChallengeInsight {
  const ChallengeInsight({
    required this.energyScore,
    required this.energyLabel,
    required this.followUp,
    required this.suggestedNextMessage,
    required this.suggestedDateIdea,
  });

  final int energyScore; // 0..100
  final String energyLabel;
  final String followUp;
  final String suggestedNextMessage;
  final String suggestedDateIdea;
}

/// Compatibility explanation: a headline score + human reasons.
class CompatibilityResult {
  const CompatibilityResult({required this.score, required this.reasons});
  final int score; // 0..100
  final List<String> reasons;
}

/// A first-date idea.
class DateIdea {
  const DateIdea({
    required this.title,
    required this.detail,
    this.lowPressure = false,
  });
  final String title;
  final String detail;
  final bool lowPressure;
}

/// Anti-ghosting coach read-out.
class GhostingCoachReport {
  const GhostingCoachReport({
    required this.balance,
    required this.momentum,
    required this.interestSignal,
    required this.suggestedAction,
    required this.balanceScore,
    required this.momentumScore,
  });

  final String balance;
  final String momentum;
  final String interestSignal;
  final String suggestedAction;
  final int balanceScore; // 0..100
  final int momentumScore; // 0..100
}

class ConnectionSamples {
  const ConnectionSamples._();

  /// Rotating set of guided icebreaker challenges.
  static const List<ChallengePrompt> challenges = <ChallengePrompt>[
    ChallengePrompt(
      title: 'Two truths, one hope',
      prompt:
          'Share two things you love and one thing you hope to do this year. '
          'Keep it playful — no pressure to impress.',
    ),
    ChallengePrompt(
      title: 'Perfect lazy Sunday',
      prompt:
          'Describe your ideal lazy Sunday in one sentence. What does it say '
          'about how you like to recharge?',
    ),
    ChallengePrompt(
      title: 'The soundtrack question',
      prompt:
          'If your week had a soundtrack, what would the first song be and '
          'why? Music says a lot about someone.',
    ),
    ChallengePrompt(
      title: 'Small joys',
      prompt:
          'What is a small, ordinary thing that reliably makes your day better? '
          'The little answers are usually the honest ones.',
    ),
  ];

  /// Picks a challenge deterministically (rotates by [seed]).
  static ChallengePrompt challengeAt(int seed) =>
      challenges[seed.abs() % challenges.length];

  /// Analyses a free-text answer and returns a polished, deterministic insight.
  static ChallengeInsight analyzeAnswer(String rawAnswer) {
    final String answer = rawAnswer.trim();
    final int words = answer.isEmpty ? 0 : answer.split(RegExp(r'\s+')).length;
    final String lower = answer.toLowerCase();

    final bool hasQuestion = answer.contains('?');
    final bool warm = _containsAny(lower, <String>[
      'love',
      'enjoy',
      'happy',
      'favourite',
      'favorite',
      'fun',
      'laugh',
      'travel',
      'music',
      'coffee',
      'walk',
      'dog',
      'cat',
    ]);

    // Energy score: rewards a bit of detail + warmth, gently.
    int score = 55 + (words.clamp(0, 30) * 1);
    if (warm) score += 8;
    if (hasQuestion) score += 6;
    score = score.clamp(40, 96);

    final String energyLabel = score >= 80
        ? 'Great energy'
        : score >= 65
            ? 'Warm and open'
            : 'Good start';

    final String followUp = words == 0
        ? 'Add a detail or two — even one specific example gives the other '
            'person something to grab onto.'
        : hasQuestion
            ? 'Nice — you left a door open with a question. Keep that curiosity '
                'going and share the "why" behind your answer.'
            : warm
                ? 'Lovely and warm. Try turning it back to them: ask what their '
                    'version of this looks like.'
                : 'Solid. Add a small personal detail so it feels like you, not '
                    'a script.';

    final String suggestedNextMessage = warm
        ? '"That’s so my vibe too. What’s the one thing that never fails to '
            'make your week better?"'
        : '"Okay, now I’m curious — what would your answer to that same '
            'question be?"';

    final String suggestedDateIdea = warm
        ? 'A relaxed coffee walk — easy to talk, easy to leave, zero pressure.'
        : 'A short casual meet-up (30–45 min) so it stays light and low-stakes.';

    return ChallengeInsight(
      energyScore: score,
      energyLabel: energyLabel,
      followUp: followUp,
      suggestedNextMessage: suggestedNextMessage,
      suggestedDateIdea: suggestedDateIdea,
    );
  }

  /// Compatibility explanation from two interest lists (falls back to a safe
  /// placeholder when data is thin). Never returns just a number.
  static CompatibilityResult compatibility({
    List<String> myInterests = const <String>[],
    List<String> theirInterests = const <String>[],
    String myIntent = '',
    String theirIntent = '',
  }) {
    final Set<String> a = _norm(myInterests);
    final Set<String> b = _norm(theirInterests);
    final Set<String> shared = a.intersection(b);

    final List<String> reasons = <String>[];
    if (shared.isNotEmpty) {
      reasons.add(
          'Shared interests: ${shared.take(3).join(', ')}');
    } else {
      reasons.add('Complementary interests that spark curiosity');
    }
    reasons.add('Similar communication style — both open and expressive');
    if (myIntent.isNotEmpty &&
        theirIntent.isNotEmpty &&
        myIntent.toLowerCase() == theirIntent.toLowerCase()) {
      reasons.add('You’re looking for the same kind of connection');
    } else {
      reasons.add('Compatible date preferences (relaxed, low-pressure plans)');
    }
    reasons.add('Similar humor level — playful, easy to banter');
    reasons.add('Good response balance in early conversations');

    // Deterministic score: base + overlap bonus.
    final int overlap = shared.length;
    int score = 68 + (overlap * 6);
    if (a.isNotEmpty && b.isNotEmpty) score += 4;
    score = score.clamp(62, 95);

    return CompatibilityResult(
        score: score, reasons: reasons.take(5).toList(growable: false));
  }

  /// Deterministic first-date ideas (3 + a clearly low-pressure option).
  static List<DateIdea> dateIdeas() => const <DateIdea>[
        DateIdea(
          title: 'Coffee walk',
          detail: '45 minutes, somewhere green. Easy to talk while you move.',
          lowPressure: true,
        ),
        DateIdea(
          title: 'Casual tapas after work',
          detail: 'Low-key, share a few small plates, no big commitment.',
        ),
        DateIdea(
          title: 'Sunday morning walk',
          detail: 'Daylight, relaxed, and a natural, easy exit if needed.',
          lowPressure: true,
        ),
      ];

  /// A short, warm message to propose a date.
  static String dateProposalMessage(String name) {
    final String who = name.trim().isEmpty ? '' : ' $name';
    return 'Hey$who — I’ve enjoyed this. Fancy a relaxed coffee walk sometime '
        'this week? No pressure, just an easy hello in person 🙂';
  }

  /// Rule-based anti-ghosting coach read-out from simple conversation signals.
  ///
  /// [myMessages]/[theirMessages] = message counts; [hoursSinceLast] = time
  /// since the last message; [iSentLast] = whether the current user sent it.
  static GhostingCoachReport coachReport({
    int myMessages = 4,
    int theirMessages = 4,
    double hoursSinceLast = 6,
    bool iSentLast = false,
  }) {
    final int total = (myMessages + theirMessages).clamp(1, 1000);
    final double share = myMessages / total;
    final int balanceScore = (100 - ((share - 0.5).abs() * 200)).round().clamp(
          0,
          100,
        );
    final String balance = balanceScore >= 75
        ? 'Your conversation is balanced.'
        : share > 0.5
            ? 'You’re carrying the conversation a bit — give them space to lead.'
            : 'They’re leading more — jump in with something of your own.';

    final int momentumScore = hoursSinceLast <= 3
        ? 92
        : hoursSinceLast <= 12
            ? 74
            : hoursSinceLast <= 36
                ? 48
                : 24;
    final String momentum = momentumScore >= 70
        ? 'Reply momentum is strong — keep it flowing.'
        : momentumScore >= 40
            ? 'Momentum is cooling. A light nudge keeps it alive.'
            : 'This has gone quiet. A short, playful restart can revive it.';

    final String interestSignal = balanceScore >= 60 && momentumScore >= 50
        ? 'Interest looks mutual and healthy.'
        : 'Mixed signals — one open question will tell you a lot.';

    final String suggestedAction = iSentLast && hoursSinceLast > 24
        ? 'You sent the last message a while ago — no more chasing. If they '
            'reply, great; if not, close it kindly and move on.'
        : hoursSinceLast > 36
            ? 'Send a short playful prompt to restart the conversation.'
            : share > 0.6
                ? 'Try asking an open question and let them talk.'
                : 'Share a small personal detail, then ask them something back.';

    return GhostingCoachReport(
      balance: balance,
      momentum: momentum,
      interestSignal: interestSignal,
      suggestedAction: suggestedAction,
      balanceScore: balanceScore,
      momentumScore: momentumScore,
    );
  }

  // --- helpers ---
  static Set<String> _norm(List<String> xs) => xs
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toSet();

  static bool _containsAny(String haystack, List<String> needles) {
    for (final String n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}
