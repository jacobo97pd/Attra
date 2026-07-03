import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Small "AI" pill used across the Connection Lab.
class LabAiChip extends StatelessWidget {
  const LabAiChip({super.key, required this.label, this.icon = Icons.auto_awesome});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[AppColors.aiPurpleDark, AppColors.aiViolet],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
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
    final Color a = accent ?? context.colors.surfaceLine;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: a.withValues(alpha: 0.45)),
      ),
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
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent.withValues(alpha: 0.16),
                context.colors.surface,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.2),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const Spacer(),
                  if (trailingLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(trailingLabel!,
                          style: TextStyle(
                              color: accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.5,
                      height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}
