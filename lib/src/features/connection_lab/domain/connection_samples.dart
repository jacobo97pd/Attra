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
          'Keep it playful. No pressure to impress.',
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

  /// Answers that carry no real content (blank, "nada", "no sé", "meh"…). These
  /// should NOT get warm feedback: the demo has to feel honest.
  static const Set<String> _emptyAnswers = <String>{
    '', 'nada', 'nose', 'nolose', 'nolo se', 'ns', 'na', 'meh', 'niidea',
    'paso', 'nada de nada', 'idk', 'dunno', 'nothing', 'none', 'x', 'xd',
    'no se', 'no lo se', 'ni idea',
  };

  /// Analyses a free-text answer and returns a deterministic insight. Low-effort
  /// or empty answers get a low score and an honest nudge to actually answer.
  static ChallengeInsight analyzeAnswer(String rawAnswer) {
    final String answer = rawAnswer.trim();
    final int words = answer.isEmpty ? 0 : answer.split(RegExp(r'\s+')).length;
    final int chars = answer.length;
    final String lower = answer.toLowerCase();
    // Normaliza para detectar respuestas de relleno: solo letras, sin signos.
    final String normalized =
        lower.replaceAll(RegExp(r'[^a-záéíóúñ\s]'), '').trim();

    // Vacía o de relleno: muy corta, o coincide con una respuesta sin contenido.
    final bool isEmpty = words == 0 ||
        normalized.length <= 2 ||
        _emptyAnswers.contains(normalized);
    final bool tooShort = !isEmpty && (words < 4 && chars < 25);

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

    // Puntuación: parte baja y sube con detalle real (palabras/longitud), calidez
    // y curiosidad. Una respuesta vacía/relleno se queda claramente abajo.
    int score;
    if (isEmpty) {
      score = 18;
    } else {
      score = 34 + (words.clamp(0, 25) * 2);
      if (warm) score += 8;
      if (hasQuestion) score += 6;
      if (chars >= 80) score += 6; // recompensa el detalle de verdad
      if (tooShort) score -= 8;
      score = score.clamp(20, 96);
    }

    final String energyLabel = score >= 80
        ? 'Great energy'
        : score >= 62
            ? 'Warm and open'
            : score >= 45
                ? 'Good start'
                : 'Needs a bit more';

    final String followUp = isEmpty
        ? 'That one’s basically blank. Share two things you love and one you '
            'want to do this year. Even a single line works.'
        : tooShort
            ? 'A little short to go on. Add a detail or an example so it '
                'actually sounds like you.'
            : hasQuestion
                ? 'Nice, you left a door open with that question. Keep the '
                    'curiosity going and say why you answered that way.'
                : warm
                    ? 'Lovely and warm. Turn it back to them and ask what their '
                        'version of this looks like.'
                    : 'Good base. Add a small personal detail so it feels like '
                        'you and not a script.';

    final String suggestedNextMessage = warm
        ? '"That’s so my vibe too. What’s the one thing that never fails to '
            'make your week better?"'
        : '"Okay, now I’m curious. What would your answer to that same '
            'question be?"';

    final String suggestedDateIdea = warm
        ? 'A relaxed coffee walk. Easy to talk, easy to leave, no pressure.'
        : 'A short, casual meet-up (about 30 to 45 min) so it stays light.';

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
    reasons.add('You both communicate in a similar way, open and expressive');
    if (myIntent.isNotEmpty &&
        theirIntent.isNotEmpty &&
        myIntent.toLowerCase() == theirIntent.toLowerCase()) {
      reasons.add('You’re looking for the same kind of connection');
    } else {
      reasons.add('Compatible date preferences (relaxed, low-pressure plans)');
    }
    reasons.add('A similar sense of humor, playful and easy to banter with');
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
    return 'Hey$who, I’ve really enjoyed this. Fancy a relaxed coffee walk '
        'sometime this week? No pressure, just an easy hello in person 🙂';
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
    // Aún no hay conversación suficiente para leer nada honestamente.
    if (myMessages + theirMessages < 3) {
      return const GhostingCoachReport(
        balance: 'Still early. Exchange a few more messages to get a read.',
        momentum: 'Not enough back-and-forth yet to judge momentum.',
        interestSignal: 'Give it a little more conversation before reading into it.',
        suggestedAction: 'Ask an easy, open question to get things going.',
        balanceScore: 50,
        momentumScore: 50,
      );
    }
    final int total = (myMessages + theirMessages).clamp(1, 1000);
    final double share = myMessages / total;
    final int balanceScore = (100 - ((share - 0.5).abs() * 200)).round().clamp(
          0,
          100,
        );
    final String balance = balanceScore >= 75
        ? 'Your conversation is balanced.'
        : share > 0.5
            ? 'You’re carrying the conversation a bit, give them some room to lead.'
            : 'They’re leading more, so jump in with something of your own.';

    final int momentumScore = hoursSinceLast <= 3
        ? 92
        : hoursSinceLast <= 12
            ? 74
            : hoursSinceLast <= 36
                ? 48
                : 24;
    final String momentum = momentumScore >= 70
        ? 'Replies are flowing nicely, keep it going.'
        : momentumScore >= 40
            ? 'Momentum is cooling. A light nudge keeps it alive.'
            : 'This has gone quiet. A short, playful restart can revive it.';

    final String interestSignal = balanceScore >= 60 && momentumScore >= 50
        ? 'Interest looks mutual and healthy.'
        : 'The signals are mixed. One open question will tell you a lot.';

    final String suggestedAction = iSentLast && hoursSinceLast > 24
        ? 'You sent the last message a while ago, so no more chasing. If they '
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
