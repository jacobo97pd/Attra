import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/date_builder.dart';

/// Date Builder (Fase 7): el usuario elige preferencias de plan y obtiene una
/// propuesta estructurada. Devuelve [DatePlanSuggestion] (place + note) que el
/// chat pasa al sheet de propuesta de cita para que la edite y envíe.
Future<DatePlanSuggestion?> showDateBuilderSheet(BuildContext context) {
  return showModalBottomSheet<DatePlanSuggestion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _DateBuilderBody(),
  );
}

class _DateBuilderBody extends StatefulWidget {
  const _DateBuilderBody();

  @override
  State<_DateBuilderBody> createState() => _DateBuilderBodyState();
}

class _DateBuilderBodyState extends State<_DateBuilderBody> {
  DatePreferences _prefs = const DatePreferences();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DatePlanSuggestion suggestion = DateBuilder.suggest(_prefs);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Crear un plan juntos',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Elige lo que te apetece y te propongo una cita.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),

            _Group<PlanType>(
              title: 'Tipo de plan',
              values: PlanType.values,
              selected: _prefs.planType,
              labelOf: (PlanType v) => v.phrase,
              onSelect: (PlanType v) =>
                  setState(() => _prefs = _prefs.copyWith(planType: v)),
            ),
            _Group<DateMoment>(
              title: 'Momento',
              values: DateMoment.values,
              selected: _prefs.moment,
              labelOf: (DateMoment v) => v.phrase,
              onSelect: (DateMoment v) =>
                  setState(() => _prefs = _prefs.copyWith(moment: v)),
            ),
            _Group<DateBudget>(
              title: 'Presupuesto',
              values: DateBudget.values,
              selected: _prefs.budget,
              labelOf: (DateBudget v) => v.phrase,
              onSelect: (DateBudget v) =>
                  setState(() => _prefs = _prefs.copyWith(budget: v)),
            ),
            _Group<DateDuration>(
              title: 'Duración',
              values: DateDuration.values,
              selected: _prefs.duration,
              labelOf: (DateDuration v) => v.phrase,
              onSelect: (DateDuration v) =>
                  setState(() => _prefs = _prefs.copyWith(duration: v)),
            ),
            _Group<DateVibe>(
              title: 'Vibe',
              values: DateVibe.values,
              selected: _prefs.vibe,
              labelOf: (DateVibe v) => v.phrase,
              onSelect: (DateVibe v) =>
                  setState(() => _prefs = _prefs.copyWith(vibe: v)),
            ),

            const SizedBox(height: 8),
            // Sugerencia (se actualiza al elegir).
            if (_prefs.planType != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.surfaceLine),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.attraRed, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(suggestion.summary,
                          style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            AttraPrimaryButton(
              label: 'Proponer esta cita',
              icon: Icons.calendar_today_rounded,
              onPressed: _prefs.isComplete
                  ? () => Navigator.of(context).pop(suggestion)
                  : null,
            ),
            if (!_prefs.isComplete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Elige una opción de cada apartado.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Group<T> extends StatelessWidget {
  const _Group({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final String title;
  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((T v) {
              final bool sel = v == selected;
              return GestureDetector(
                onTap: () => onSelect(v),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.attraRed.withValues(alpha: 0.18)
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    border: Border.all(
                        color: sel ? AppColors.attraRed : AppColors.surfaceLine),
                  ),
                  child: Text(labelOf(v),
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }
}
