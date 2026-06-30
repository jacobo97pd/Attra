import 'package:flutter/material.dart';

import '../../../theme/theme_controller.dart';
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
  });

  final SettingsController controller;

  /// Cambia el modo de tema (claro/oscuro/sistema). Persiste en ajustes.
  final Future<void> Function(ThemeMode mode)? onSetThemeMode;

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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // +2 = sección Apariencia (tema) + "Cómo funciona Attra" (tutorial).
          itemCount: sections.length + 2,
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
            final SettingsSection section = sections[index - 2];
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
