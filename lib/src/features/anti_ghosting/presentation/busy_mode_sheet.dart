import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Resultado al activar el modo ocupado.
typedef BusyModeChoice = ({
  DateTime until,
  String reason,
  bool visibleToMatches,
});

/// Bottom sheet para activar el **Modo ocupado** (Attra Clear §4/§15). Elige
/// duración (3/7/14 días o personalizada) y si los matches lo ven. Devuelve
/// `null` si se cancela.
class BusyModeSheet extends StatefulWidget {
  const BusyModeSheet({super.key});

  static Future<BusyModeChoice?> show(BuildContext context) {
    return showModalBottomSheet<BusyModeChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BusyModeSheet(),
    );
  }

  @override
  State<BusyModeSheet> createState() => _BusyModeSheetState();
}

class _BusyModeSheetState extends State<BusyModeSheet> {
  static const List<int> _presetDays = <int>[3, 7, 14];
  int? _selectedDays = 7;
  DateTime? _customUntil;
  bool _visible = true;

  DateTime? get _until {
    if (_customUntil != null) return _customUntil;
    if (_selectedDays != null) {
      return DateTime.now().add(Duration(days: _selectedDays!));
    }
    return null;
  }

  Future<void> _pickCustom() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() {
        _customUntil = DateTime(picked.year, picked.month, picked.day, 23, 59);
        _selectedDays = null;
      });
    }
  }

  void _confirm() {
    final DateTime? until = _until;
    if (until == null) return;
    Navigator.of(context).pop<BusyModeChoice>(
      (until: until, reason: '', visibleToMatches: _visible),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  const Icon(Icons.bedtime_outlined,
                      color: AppColors.attraRed, size: 22),
                  const SizedBox(width: 8),
                  Text('Modo ocupado',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pausa tu actividad durante unos días y avisa suavemente a tus '
                'matches. No se contará como ghosting mientras estés en pausa.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.textSecondary),
              ),
              const SizedBox(height: 18),
              Text('¿Cuánto tiempo?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final int d in _presetDays)
                    _ChoiceChip(
                      label: '$d días',
                      selected: _selectedDays == d && _customUntil == null,
                      onTap: () => setState(() {
                        _selectedDays = d;
                        _customUntil = null;
                      }),
                    ),
                  _ChoiceChip(
                    label: _customUntil == null
                        ? 'Personalizado'
                        : 'Hasta ${_fmtDate(_customUntil!)}',
                    selected: _customUntil != null,
                    onTap: _pickCustom,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _visible,
                onChanged: (bool v) => setState(() => _visible = v),
                title: const Text('Avisar a mis matches'),
                subtitle: Text(
                  'Verán que estás en modo ocupado en el chat.',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                activeThumbColor: AppColors.attraRed,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.attraRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _until == null ? null : _confirm,
                  child: const Text('Activar modo ocupado',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.attraRed.withValues(alpha: 0.14)
          : context.colors.surfaceHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.attraRed.withValues(alpha: 0.5)
                  : context.colors.surfaceLine,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.attraRed : context.colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}
