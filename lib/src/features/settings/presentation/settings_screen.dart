import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/theme_controller.dart';
import '../../anti_ghosting/presentation/busy_mode_sheet.dart';
import '../../tutorial/presentation/tutorial_screen.dart';
import '../domain/settings_catalog.dart';
import '../domain/setting_definition.dart';
import 'settings_controller.dart';
import 'settings_icons.dart';
import 'settings_section_screen.dart';

/// Pantalla raiz de Ajustes: apariencia (tema) + las 8 secciones del catalogo.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.onSetThemeMode,
    this.busyModeFeatureEnabled = false,
    this.initialBusyUntil,
    this.onSetBusyMode,
  });

  final SettingsController controller;

  /// Cambia el modo de tema (claro/oscuro/sistema). Persiste en ajustes.
  final Future<void> Function(ThemeMode mode)? onSetThemeMode;

  /// Attra Clear §4: muestra la entrada de Modo ocupado si el flag está activo.
  final bool busyModeFeatureEnabled;
  final DateTime? initialBusyUntil;
  final Future<void> Function({
    required bool enabled,
    DateTime? until,
    String reason,
    bool visibleToMatches,
  })? onSetBusyMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  void _openSection(SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsSectionScreen(
          controller: widget.controller,
          sectionKey: section.key,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<SettingsSection> sections = SettingsCatalog.sections;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, _) {
        // Cabeceras fijas: Apariencia (0), Tutorial (1) y, si procede, Modo
        // ocupado (2). Las secciones del catálogo van detrás.
        final bool showBusy =
            widget.busyModeFeatureEnabled && widget.onSetBusyMode != null;
        final int leading = showBusy ? 3 : 2;
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sections.length + leading,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return _ThemeModeTile(onSetThemeMode: widget.onSetThemeMode);
            }
            if (index == 1) {
              return ListTile(
                leading: Icon(
                  Icons.help_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text(
                  'Cómo funciona Attra',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Vuelve a ver el tutorial de bienvenida'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => TutorialScreen.show(context),
              );
            }
            if (showBusy && index == 2) {
              return _BusyModeTile(
                initialUntil: widget.initialBusyUntil,
                onSetBusyMode: widget.onSetBusyMode!,
              );
            }
            final SettingsSection section = sections[index - leading];
            final bool destructive =
                section.key == SettingsCatalog.secLifecycle;
            return ListTile(
              leading: Icon(
                settingsIcon(section.icon),
                color: destructive
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                section.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color:
                      destructive ? Theme.of(context).colorScheme.error : null,
                ),
              ),
              subtitle: Text(section.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSection(section),
            );
          },
        );
      },
    );
  }
}

/// Attra Clear §4: entrada de Modo ocupado. Autónomo (estado optimista local)
/// para reflejar el cambio al instante sin depender de recargar la pantalla.
class _BusyModeTile extends StatefulWidget {
  const _BusyModeTile({required this.initialUntil, required this.onSetBusyMode});

  final DateTime? initialUntil;
  final Future<void> Function({
    required bool enabled,
    DateTime? until,
    String reason,
    bool visibleToMatches,
  }) onSetBusyMode;

  @override
  State<_BusyModeTile> createState() => _BusyModeTileState();
}

class _BusyModeTileState extends State<_BusyModeTile> {
  DateTime? _until;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Expiración defensiva: si la fecha ya pasó, se considera inactivo.
    final DateTime? u = widget.initialUntil;
    _until = (u != null && u.isAfter(DateTime.now())) ? u : null;
  }

  bool get _active => _until != null;

  Future<void> _toggle() async {
    if (_busy) return;
    if (_active) {
      setState(() => _busy = true);
      await widget.onSetBusyMode(enabled: false);
      if (mounted) {
        setState(() {
          _until = null;
          _busy = false;
        });
      }
      return;
    }
    final BusyModeChoice? choice = await BusyModeSheet.show(context);
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    await widget.onSetBusyMode(
      enabled: true,
      until: choice.until,
      visibleToMatches: choice.visibleToMatches,
    );
    if (mounted) {
      setState(() {
        _until = choice.until;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = _active
        ? 'Activo hasta ${_fmt(_until!)} · toca para desactivar'
        : 'Pausa tu actividad y avisa suavemente a tus matches';
    return ListTile(
      leading: Icon(Icons.bedtime_outlined,
          color: _active ? AppColors.attraRed : theme.colorScheme.primary),
      title: Row(
        children: <Widget>[
          const Text('Modo ocupado',
              style: TextStyle(fontWeight: FontWeight.w600)),
          if (_active) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.attraRed.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text('Activo',
                  style: TextStyle(
                      color: AppColors.attraRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_active ? Icons.toggle_on : Icons.chevron_right,
              color: _active ? AppColors.attraRed : null, size: _active ? 30 : 24),
      onTap: _busy ? null : _toggle,
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Sección "Apariencia": elige Sistema / Claro / Oscuro. Refleja el estado del
/// ThemeController (cambia al instante) y persiste vía [onSetThemeMode].
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({this.onSetThemeMode});

  final Future<void> Function(ThemeMode mode)? onSetThemeMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (BuildContext context, ThemeMode mode, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.brightness_6_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text('Apariencia',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('Sistema')),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Claro')),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Oscuro')),
                ],
                selected: <ThemeMode>{mode},
                showSelectedIcon: false,
                onSelectionChanged: onSetThemeMode == null
                    ? null
                    : (Set<ThemeMode> sel) => onSetThemeMode!(sel.first),
              ),
            ],
          ),
        );
      },
    );
  }
}
