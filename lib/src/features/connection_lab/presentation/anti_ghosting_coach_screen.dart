import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../domain/connection_samples.dart';
import 'lab_widgets.dart';

/// Anti-Ghosting Coach: reads simple conversation signals (balance, momentum,
/// interest) and suggests the next healthy action. Uses rule-based analysis so
/// it works with or without a live conversation. When opened from a real chat,
/// pass the message counts / timing to get a tailored read-out.
class AntiGhostingCoachScreen extends StatelessWidget {
  const AntiGhostingCoachScreen({
    super.key,
    this.otherName,
    this.myMessages = 5,
    this.theirMessages = 4,
    this.hoursSinceLast = 20,
    this.iSentLast = true,
  });

  final String? otherName;
  final int myMessages;
  final int theirMessages;
  final double hoursSinceLast;
  final bool iSentLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhostingCoachReport r = ConnectionSamples.coachReport(
      myMessages: myMessages,
      theirMessages: theirMessages,
      hoursSinceLast: hoursSinceLast,
      iSentLast: iSentLast,
    );
    final String who = (otherName ?? '').trim();

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('Anti-Ghosting Coach')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'Conversation health', icon: Icons.favorite_rounded),
          const SizedBox(height: 12),
          Text(
            who.isEmpty
                ? 'Here’s how this kind of conversation is going.'
                : 'Here’s how your conversation with $who is going.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          _MeterCard(
            icon: Icons.balance_rounded,
            title: 'Conversation balance',
            body: r.balance,
            score: r.balanceScore,
            accent: AppColors.aiViolet,
          ),
          const SizedBox(height: 10),
          _MeterCard(
            icon: Icons.speed_rounded,
            title: 'Reply momentum',
            body: r.momentum,
            score: r.momentumScore,
            accent: AppColors.success,
          ),
          const SizedBox(height: 10),
          LabCard(
            child: _Line(
              icon: Icons.insights_rounded,
              title: 'Interest signal',
              body: r.interestSignal,
              accent: AppColors.gold,
            ),
          ),
          const SizedBox(height: 14),
          LabCard(
            accent: AppColors.attraRed,
            child: _Line(
              icon: Icons.tips_and_updates_rounded,
              title: 'Suggested next action',
              body: r.suggestedAction,
              accent: AppColors.attraRed,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Attra never auto-sends anything. You always choose what to say, and '
            'you can always close a conversation with respect.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.score,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final int score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LabCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$score%',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 7,
              backgroundColor: context.colors.surfaceLine,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(body,
              style: TextStyle(
                  color: context.colors.textSecondary, height: 1.35)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body,
                  style: TextStyle(
                      color: context.colors.textSecondary, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
