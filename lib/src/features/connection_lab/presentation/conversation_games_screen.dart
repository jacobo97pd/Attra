import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_buttons.dart';
import 'demo_challenge_screen.dart';
import 'lab_widgets.dart';

/// "Play" hub: showcases Attra's AI conversation games and lets anyone try the
/// interactive Demo Challenge right now (no match required). Real games run
/// inside a match's chat; this hub explains them and routes to Discover.
class ConversationGamesScreen extends StatelessWidget {
  const ConversationGamesScreen({super.key, this.onDiscover});

  /// Opens the discovery feed to find someone to play with.
  final VoidCallback? onDiscover;

  static const List<_Game> _games = <_Game>[
    _Game(
      icon: Icons.psychology_alt_rounded,
      title: 'Break the Ice',
      body: 'AI-guided prompts that get a real conversation going fast.',
      accent: AppColors.aiViolet,
    ),
    _Game(
      icon: Icons.bolt_rounded,
      title: 'Attra Spark',
      body: 'A 5-minute live mini-game you both play to break the ice.',
      accent: AppColors.attraRed,
    ),
    _Game(
      icon: Icons.compare_arrows_rounded,
      title: 'This or That',
      body: 'Quick either/or rounds that reveal your vibe in seconds.',
      accent: AppColors.gold,
    ),
    _Game(
      icon: Icons.workspace_premium_rounded,
      title: 'Two Truths & a Lie',
      body: 'A playful guessing game to learn something real about each other.',
      accent: AppColors.success,
    ),
    _Game(
      icon: Icons.forum_rounded,
      title: 'Double Answer',
      body: 'You both answer the same question, then compare — instant banter.',
      accent: AppColors.nightBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('Play')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'Conversation games'),
          const SizedBox(height: 12),
          Text('Games that turn a match into a real conversation',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Attra is built around playing and talking, not just swiping. Try a '
            'guided challenge now — no match needed.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          // Try it now.
          LabCard(
            accent: AppColors.aiViolet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome, color: AppColors.aiViolet),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Try a Demo Challenge',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Experience the AI-guided conversation flow end to end, right '
                  'now.',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 12),
                AttraPrimaryButton(
                  label: 'Start Demo Challenge',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DemoChallengeScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('All conversation games',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ..._games.map((_Game g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: g.accent.withValues(alpha: 0.18),
                        ),
                        child: Icon(g.icon, color: g.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(g.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(g.body,
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 12.5,
                                    height: 1.3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 6),
          if (onDiscover != null)
            AttraGhostButton(
              label: 'Find someone to play with',
              onPressed: onDiscover,
            ),
        ],
      ),
    );
  }
}

class _Game {
  const _Game({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}
