import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/attra_colors.dart';

/// Content-sized tiles. Columns respond to available space and reading size;
/// no fixed aspect ratio can crop a translation or a personal response.
class AttraAdaptiveGrid extends StatelessWidget {
  const AttraAdaptiveGrid(
      {super.key,
      required this.children,
      this.columns = 2,
      this.minTileWidth = 280,
      this.gap = AppSpacing.lg});

  final List<Widget> children;
  final int columns;
  final double minTileWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double scale = MediaQuery.textScalerOf(context).scale(17) / 17;
          final double minimum = minTileWidth * (scale > 1.3 ? scale / 1.3 : 1);
          final int count = ((constraints.maxWidth + gap) / (minimum + gap))
              .floor()
              .clamp(1, columns);
          final double width =
              (constraints.maxWidth - (count - 1) * gap) / count;
          return Wrap(spacing: gap, runSpacing: gap, children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: width, child: child),
          ]);
        },
      );
}

/// A readable content column shared by profiles, discovery and conversations.
/// Insets remain explicit so media and text can share the same leading edge.
class AttraContentFrame extends StatelessWidget {
  const AttraContentFrame({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.readingWidth,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding,
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      );
}

/// Section hierarchy without a second card around the content it introduces.
class AttraSectionHeading extends StatelessWidget {
  const AttraSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(header: true, child: Text(title, style: text.titleLarge)),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle!, style: text.bodySmall),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (trailing == null) return heading;
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(17) > 24) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        );
      },
    );
  }
}

/// A personal response: a quiet question followed by the person's own words.
class AttraPromptNote extends StatelessWidget {
  const AttraPromptNote({
    super.key,
    required this.question,
    required this.answer,
    this.trailing,
    this.onTap,
  });

  final String question;
  final String answer;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(question, style: text.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Text(answer, style: text.titleLarge),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Align(alignment: AlignmentDirectional.centerEnd, child: trailing!),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: content,
      ),
    );
  }
}

/// Photo and the comment it prompted, read as one object rather than nested cards.
/// The caller owns media loading, privacy, and every action.
class AttraPhotoNote extends StatelessWidget {
  const AttraPhotoNote({
    super.key,
    required this.eyebrow,
    this.title,
    this.body,
    this.photo,
    this.footer,
  });

  final String eyebrow;
  final String? title;
  final String? body;
  final Widget? photo;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (photo != null) photo!,
          Padding(
            padding: AppSpacing.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(eyebrow, style: text.bodySmall),
                if (title != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(title!, style: text.titleMedium),
                ],
                if (body != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(body!, style: text.bodyLarge),
                ],
                if (footer != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  footer!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
