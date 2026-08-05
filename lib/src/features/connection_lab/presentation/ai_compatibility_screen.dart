import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../domain/connection_samples.dart';
import 'lab_widgets.dart';

/// AI Compatibility Insights: shows a headline score AND the human reasons
/// behind it (never just a percentage). Uses real interests/intent when
/// available, otherwise a safe placeholder derived from what we know.
class AiCompatibilityScreen extends StatelessWidget {
  const AiCompatibilityScreen({
    super.key,
    this.otherName,
    this.myInterests = const <String>[],
    this.theirInterests = const <String>[],
    this.myIntent = '',
    this.theirIntent = '',
  });

  final String? otherName;
  final List<String> myInterests;
  final List<String> theirInterests;
  final String myIntent;
  final String theirIntent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CompatibilityResult r = ConnectionSamples.compatibility(
      myInterests: myInterests,
      theirInterests: theirInterests,
      myIntent: myIntent,
      theirIntent: theirIntent,
    );
    final String who = (otherName ?? '').trim();

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('AI Compatibility')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'AI compatibility'),
          const SizedBox(height: 16),
          // Score ring.
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: r.score / 100,
                      strokeWidth: 12,
                      backgroundColor: context.colors.surfaceLine,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.aiViolet),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('${r.score}%',
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      Text('compatible',
                          style: TextStyle(color: context.colors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            who.isEmpty
                ? 'Why you might click'
                : 'Why you and $who might click',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...r.reasons.map((String reason) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle_rounded,
                          size: 20, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(reason,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                height: 1.3)),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Text(
            'Compatibility is a starting point, not a verdict. The best signal '
            'is how a real conversation feels.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}
