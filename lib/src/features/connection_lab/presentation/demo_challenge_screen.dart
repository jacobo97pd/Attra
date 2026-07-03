import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/connection_samples.dart';
import 'lab_widgets.dart';

/// Interactive "Demo Challenge": lets anyone (new users without matches,
/// reviewers) experience Attra's AI-guided conversation flow end to end —
/// prompt → your answer → follow-up → energy insight → suggested next message /
/// date idea. Fully offline & deterministic, so it always works.
class DemoChallengeScreen extends StatefulWidget {
  const DemoChallengeScreen({super.key});

  @override
  State<DemoChallengeScreen> createState() => _DemoChallengeScreenState();
}

class _DemoChallengeScreenState extends State<DemoChallengeScreen> {
  final TextEditingController _answer = TextEditingController();
  int _seed = 0;
  ChallengeInsight? _insight;

  ChallengePrompt get _prompt => ConnectionSamples.challengeAt(_seed);

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    setState(() => _insight = ConnectionSamples.analyzeAnswer(_answer.text));
  }

  void _another() {
    setState(() {
      _seed += 1;
      _insight = null;
      _answer.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChallengeInsight? insight = _insight;
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        title: const Text('Demo Challenge'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'AI-guided conversation'),
          const SizedBox(height: 12),
          // The prompt.
          LabCard(
            accent: AppColors.aiViolet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.aiViolet),
                    const SizedBox(width: 8),
                    Text(_prompt.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_prompt.prompt,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(height: 1.35, color: context.colors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Your answer',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _answer,
            minLines: 2,
            maxLines: 5,
            maxLength: 400,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Type how you would respond…',
              filled: true,
              fillColor: context.colors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 4),
          AttraPrimaryButton(
            label: insight == null ? 'Get AI feedback' : 'Re-analyze',
            icon: Icons.psychology_alt_rounded,
            onPressed: _analyze,
          ),
          if (insight != null) ...<Widget>[
            const SizedBox(height: 20),
            _EnergyMeter(insight: insight),
            const SizedBox(height: 12),
            LabCard(
              child: _InsightRow(
                icon: Icons.forum_rounded,
                title: 'Follow-up suggestion',
                body: insight.followUp,
              ),
            ),
            const SizedBox(height: 10),
            LabCard(
              child: _InsightRow(
                icon: Icons.send_rounded,
                title: 'Suggested next message',
                body: insight.suggestedNextMessage,
                accent: AppColors.attraRed,
              ),
            ),
            const SizedBox(height: 10),
            LabCard(
              child: _InsightRow(
                icon: Icons.local_cafe_rounded,
                title: 'Suggested date idea',
                body: insight.suggestedDateIdea,
                accent: AppColors.gold,
              ),
            ),
            const SizedBox(height: 16),
            AttraGhostButton(label: 'Try another challenge', onPressed: _another),
          ],
        ],
      ),
    );
  }
}

class _EnergyMeter extends StatelessWidget {
  const _EnergyMeter({required this.insight});
  final ChallengeInsight insight;

  @override
  Widget build(BuildContext context) {
    return LabCard(
      accent: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bolt_rounded, size: 18, color: AppColors.success),
              const SizedBox(width: 8),
              Text('Conversation energy',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${insight.energyScore}%  ·  ${insight.energyLabel}',
                  style: const TextStyle(
                      color: AppColors.success, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: insight.energyScore / 100,
              minHeight: 8,
              backgroundColor: context.colors.surfaceLine,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.body,
    this.accent = AppColors.aiViolet,
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
