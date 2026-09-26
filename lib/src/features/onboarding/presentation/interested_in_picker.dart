import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../profile/domain/profile_trait.dart';
import '../domain/interested_in.dart';

/// Selector de "Me interesan" (Mujer / Hombre / No binario, multi-selección).
///
/// Es el MISMO control que el paso de preferencias del onboarding, sacado aquí
/// para que el selector de modo y el editor del perfil pregunten exactamente
/// lo mismo y con el mismo aspecto: si cada pantalla tuviera su lista, las
/// casillas acabarían divergiendo de las que entiende GenderMatching.
class InterestedInPicker extends StatelessWidget {
  const InterestedInPicker({
    super.key,
    required this.title,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String value) {
    final List<String> next = List<String>.from(selected);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: InterestedIn.options.map((TraitOption option) {
            return SelectablePill(
              key: ValueKey<String>('interested-in-${option.value}'),
              label: option.label,
              selected: selected.contains(option.value),
              onTap: () => _toggle(option.value),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

/// Pill seleccionable animada: grafito cuando está apagada, degradado de marca
/// con check cuando está activa.
class SelectablePill extends StatelessWidget {
  const SelectablePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding:
            EdgeInsets.symmetric(horizontal: selected ? 14 : 16, vertical: 10),
        decoration: BoxDecoration(
          gradient:
              selected ? const LinearGradient(colors: AppColors.action) : null,
          color: selected ? null : context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? Colors.transparent : context.colors.surfaceLine,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              Icon(Icons.check_rounded,
                  size: 16, color: context.colors.textPrimary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
