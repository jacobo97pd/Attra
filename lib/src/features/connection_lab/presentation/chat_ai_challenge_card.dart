import 'package:flutter/material.dart';

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
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome,
                  size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AI Challenge',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Start an AI-guided challenge to break the ice and keep the '
            'conversation flowing.',
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.5,
                height: 1.3),
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
    return primary
        ? FilledButton.icon(
            onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label))
        : TextButton.icon(
            onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label));
  }
}
