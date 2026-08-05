import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import 'ai_compatibility_screen.dart';
import 'anti_ghosting_coach_screen.dart';
import 'date_planner_screen.dart';
import 'demo_challenge_screen.dart';
import 'lab_widgets.dart';

/// Attra Connection Lab — the primary post-login landing.
///
/// It reframes Attra as an AI-powered *connection* product: guided
/// conversations, anti-ghosting coaching, compatibility insights, conversation
/// games and date planning. The existing swipe/discovery flow lives behind the
/// "Discover People" card and the Discover tab.
class ConnectionLabScreen extends StatelessWidget {
  const ConnectionLabScreen({
    super.key,
    this.displayName,
    this.myInterests = const <String>[],
    this.myIntent = '',
    required this.onDiscover,
    required this.onOpenPlay,
  });

  final String? displayName;
  final List<String> myInterests;
  final String myIntent;

  /// Switches to the Discover tab (existing feed).
  final VoidCallback onDiscover;

  /// Switches to the Play tab (conversation games hub).
  final VoidCallback onOpenPlay;

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String hello =
        (displayName ?? '').trim().isEmpty ? '' : ', ${displayName!.trim()}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        const LabAiChip(label: 'AI-powered connections'),
        const SizedBox(height: 12),
        Text('Attra Connection Lab$hello',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          'AI-guided conversations, compatibility insights and anti-ghosting '
          'tools to help you build real connections.',
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: context.colors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 14),
        const _ValueStrip(),
        const SizedBox(height: 18),

        // 6 feature cards in a 2-column grid.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.92,
          children: <Widget>[
            LabBigCard(
              icon: Icons.psychology_alt_rounded,
              title: 'Break the Ice',
              subtitle: 'AI-guided prompts that spark real conversation.',
              accent: AppColors.aiViolet,
              trailingLabel: 'Try it',
              onTap: () => _push(context, const DemoChallengeScreen()),
            ),
            LabBigCard(
              icon: Icons.sports_esports_rounded,
              title: 'Conversation Games',
              subtitle: 'Playful games that turn a match into a real chat.',
              accent: AppColors.attraRed,
              onTap: onOpenPlay,
            ),
            LabBigCard(
              icon: Icons.favorite_rounded,
              title: 'Anti-Ghosting Coach',
              subtitle: 'Keep conversations alive with healthy nudges.',
              accent: AppColors.success,
              onTap: () => _push(context, const AntiGhostingCoachScreen()),
            ),
            LabBigCard(
              icon: Icons.insights_rounded,
              title: 'AI Compatibility',
              subtitle:
                  'See why you might click, with reasons and not just a %.',
              accent: AppColors.gold,
              onTap: () => _push(
                context,
                AiCompatibilityScreen(
                  myInterests: myInterests,
                  myIntent: myIntent,
                ),
              ),
            ),
            LabBigCard(
              icon: Icons.event_available_rounded,
              title: 'Date Planner',
              subtitle: 'Easy first-date ideas and a message to propose them.',
              accent: AppColors.nightBlue,
              onTap: () => _push(context, const DatePlannerScreen()),
            ),
            LabBigCard(
              icon: Icons.explore_rounded,
              title: 'Discover People',
              subtitle: 'Meet compatible people and start something.',
              accent: AppColors.wineRed,
              onTap: onDiscover,
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact value proposition strip: the five things Attra does.
class _ValueStrip extends StatelessWidget {
  const _ValueStrip();

  static const List<({IconData icon, String text})> _items =
      <({IconData icon, String text})>[
    (icon: Icons.forum_rounded, text: 'Better conversations'),
    (icon: Icons.shield_moon_rounded, text: 'Less ghosting'),
    (icon: Icons.auto_awesome, text: 'AI-guided challenges'),
    (icon: Icons.insights_rounded, text: 'Compatibility insights'),
    (icon: Icons.local_cafe_rounded, text: 'From match to date'),
  ];

  @override
  Widget build(BuildContext context) {
    return LabCard(
      accent: AppColors.aiViolet,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _items.length; i++) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(_items[i].icon, size: 18, color: AppColors.aiViolet),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_items[i].text,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.check_rounded,
                    size: 16, color: AppColors.success),
              ],
            ),
            if (i != _items.length - 1)
              Divider(height: 16, color: context.colors.surfaceLine),
          ],
        ],
      ),
    );
  }
}
