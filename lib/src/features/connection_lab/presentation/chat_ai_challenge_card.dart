import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Prominent card shown at the top of every match conversation, inviting the
/// pair into Attra's AI-guided challenges instead of a blank chat. The normal
/// chat remains fully available below.
class ChatAiChallengeCard extends StatelessWidget {
  const ChatAiChallengeCard({
    super.key,
    required this.onStartChallenge,
    required this.onSuggestOpener,
    required this.onPlayGame,
  });

  final VoidCallback onStartChallenge;
  final VoidCallback onSuggestOpener;
  final VoidCallback onPlayGame;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.aiViolet.withValues(alpha: 0.20),
            context.colors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.aiViolet.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.aiViolet),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI Challenge',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Start an AI-guided challenge to break the ice and keep the '
            'conversation flowing.',
            style: TextStyle(
                color: context.colors.textSecondary, fontSize: 12.5, height: 1.3),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Btn(
                label: 'Start Challenge',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onTap: onStartChallenge,
              ),
              _Btn(
                label: 'Suggest opener',
                icon: Icons.lightbulb_outline_rounded,
                onTap: onSuggestOpener,
              ),
              _Btn(
                label: 'Play quick game',
                icon: Icons.sports_esports_rounded,
                onTap: onPlayGame,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Color bg = primary ? AppColors.aiViolet : context.colors.surfaceHigh;
    final Color fg = primary ? Colors.white : context.colors.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: primary
                ? null
                : Border.all(color: context.colors.surfaceLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
