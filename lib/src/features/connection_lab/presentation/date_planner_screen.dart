import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/connection_samples.dart';
import 'lab_widgets.dart';

/// AI Date Planner: suggests 3 low-key first-date ideas plus a ready-to-send
/// message to propose it. Highlights a clearly low-pressure option. Optional
/// [onSendProposal] lets a chat screen wire it to a real message.
class DatePlannerScreen extends StatelessWidget {
  const DatePlannerScreen({
    super.key,
    this.otherName,
    this.onSendProposal,
  });

  final String? otherName;

  /// If provided (e.g. from a chat), called with the proposal text.
  final void Function(String message)? onSendProposal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<DateIdea> ideas = ConnectionSamples.dateIdeas();
    final String message = ConnectionSamples.dateProposalMessage(otherName ?? '');

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('AI Date Planner')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'From match to date', icon: Icons.event_available_rounded),
          const SizedBox(height: 12),
          Text('Easy first-date ideas',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Low-key plans that make it easy to say yes.',
              style: TextStyle(color: context.colors.textSecondary)),
          const SizedBox(height: 14),
          ...ideas.map((DateIdea idea) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  accent: idea.lowPressure ? AppColors.success : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        idea.lowPressure
                            ? Icons.spa_rounded
                            : Icons.local_dining_rounded,
                        color: idea.lowPressure
                            ? AppColors.success
                            : AppColors.gold,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text(idea.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                if (idea.lowPressure) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text('Low pressure',
                                        style: TextStyle(
                                            color: AppColors.success,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(idea.detail,
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    height: 1.3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Text('A message to propose it',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          LabCard(
            accent: AppColors.attraRed,
            child: Text('"$message"',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    height: 1.4,
                    fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 12),
          if (onSendProposal != null)
            AttraPrimaryButton(
              label: 'Use this message',
              icon: Icons.send_rounded,
              onPressed: () {
                onSendProposal!(message);
                Navigator.of(context).maybePop();
              },
            )
          else
            AttraGhostButton(
              label: 'Copy message',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
        ],
      ),
    );
  }
}
