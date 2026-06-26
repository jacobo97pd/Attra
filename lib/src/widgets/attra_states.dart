import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'attra_buttons.dart';

/// Estado vacío premium reutilizable: icono en halo, título, texto y CTA.
class AttraEmptyState extends StatelessWidget {
  const AttraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: <Color>[
                  AppColors.attraRed.withValues(alpha: 0.22),
                  Colors.transparent,
                ]),
              ),
              child: Icon(icon, size: 44, color: AppColors.attraRed),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              AttraPrimaryButton(
                  label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cabecera de sección consistente (título + acción opcional a la derecha).
class AttraSectionHeader extends StatelessWidget {
  const AttraSectionHeader(this.title,
      {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Skeleton loader con shimmer suave (sustituye spinners genéricos).
class AttraSkeleton extends StatefulWidget {
  const AttraSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppSpacing.radiusSm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<AttraSkeleton> createState() => _AttraSkeletonState();
}

class _AttraSkeletonState extends State<AttraSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * _c.value, 0),
              end: Alignment(1 - 2 * _c.value, 0),
              colors: const <Color>[
                AppColors.surfaceHigh,
                AppColors.surfaceLine,
                AppColors.surfaceHigh,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton de una card de perfil del feed (ocupa la pantalla).
class AttraProfileCardSkeleton extends StatelessWidget {
  const AttraProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Expanded(
            child: AttraSkeleton(
                height: double.infinity, radius: AppSpacing.radiusLg),
          ),
          const SizedBox(height: AppSpacing.md),
          AttraSkeleton(
              width: MediaQuery.of(context).size.width * 0.5, height: 22),
          const SizedBox(height: AppSpacing.sm),
          const AttraSkeleton(width: 180, height: 14),
        ],
      ),
    );
  }
}
