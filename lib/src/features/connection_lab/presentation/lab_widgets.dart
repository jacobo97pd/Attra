import 'package:flutter/material.dart';
import '../../../widgets/attra_motion.dart';

import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_badges.dart';
import '../../../widgets/attra_backgrounds.dart';

/// Small "AI" pill used across the Connection Lab.
class LabAiChip extends StatelessWidget {
  const LabAiChip(
      {super.key, required this.label, this.icon = Icons.auto_awesome});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AttraLabel(label: label, icon: icon),
    );
  }
}

/// A soft surface card with an optional left accent tint. Base container for the
/// Connection Lab insight/read-out sections.
class LabCard extends StatelessWidget {
  const LabCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final Color? accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AttraCard(
      padding: padding,
      child: child,
    );
  }
}

/// Large tappable feature card used on the Connection Lab landing grid.
class LabBigCard extends StatelessWidget {
  const LabBigCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.trailingLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  /// Optional badge (e.g. "Try it") shown top-right.
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AttraPressFeedback(
        child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon,
                        color: context.colors.textSecondary, size: 24)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                      Text(title, style: text.titleMedium),
                      const SizedBox(height: 8),
                      Text(subtitle, style: text.bodySmall),
                      if (trailingLabel != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(trailingLabel!, style: text.labelMedium),
                      ],
                    ])),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: context.colors.textMuted, size: 20),
              ]),
        ),
      ),
    ));
  }
}
