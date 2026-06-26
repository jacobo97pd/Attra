import 'package:flutter/material.dart';

import '../domain/settings_catalog.dart';
import '../domain/setting_definition.dart';
import 'settings_controller.dart';
import 'settings_icons.dart';
import 'settings_section_screen.dart';

/// Pantalla raiz de Ajustes: lista las 8 secciones del catalogo.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final SettingsController controller;

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
          itemCount: sections.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final SettingsSection section = sections[index];
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
