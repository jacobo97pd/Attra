import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../onboarding/presentation/interested_in_picker.dart';

/// Paso "¿A quién quieres conocer?" que ocupa el sitio del feed de Descubrir
/// mientras falte "Me interesan" en citas (ver InterestedIn.promptBeforeFeed).
///
/// POR QUÉ ASÍ Y NO UNA HOJA MODAL: quien ya estaba en citas con la lista vacía
/// veía (y le veían) todos los géneros, así que el feed de citas no debe
/// cargarse hasta que conteste; pero bloquear la app entera por esto dejaría a
/// alguien sin sus chats. Aquí no hay forma de saltárselo para ver perfiles, y
/// las demás pestañas (conexiones, chats, perfil) siguen a mano.
///
/// Guardar no se activa sin al menos una casilla: guardar la lista vacía es
/// justo el fallo que se arregla. Si falla, se avisa y se puede reintentar.
class InterestedInGate extends StatefulWidget {
  const InterestedInGate({
    super.key,
    required this.onSave,
    this.onChangeMode,
    this.actions = const <Widget>[],
  });

  /// Guarda `preferences.interestedIn` (nunca vacío). Al recargarse el usuario
  /// con la lista puesta, el HomeShell cambia este paso por el feed.
  final Future<void> Function(List<String> values) onSave;

  /// Abre "Qué buscas": quien no quiere citas puede pasarse a amistad o grupos
  /// en vez de contestar. Null = sin ese atajo.
  final VoidCallback? onChangeMode;

  /// Acciones de la cabecera del feed (p. ej. la campana), para que sigan a
  /// mano mientras el feed no se enseña.
  final List<Widget> actions;

  @override
  State<InterestedInGate> createState() => _InterestedInGateState();
}

class _InterestedInGateState extends State<InterestedInGate> {
  List<String> _selected = const <String>[];
  bool _saving = false;

  Future<void> _save() async {
    final List<String> picked = List<String>.unmodifiable(_selected);
    if (picked.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(picked);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('No se pudo guardar. Inténtalo de nuevo.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          if (widget.actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  right: AppSpacing.sm, top: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: widget.actions,
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(Icons.favorite_rounded,
                          size: 40, color: context.colors.accent),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '¿A quién quieres conocer?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Para enseñarte perfiles de citas necesitamos saberlo. '
                        'Solo se usa para citas: verás a estas personas y te '
                        'verán quienes también te buscan a ti. Podrás cambiarlo '
                        'en tu perfil.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      InterestedInPicker(
                        title: 'Me interesan',
                        selected: _selected,
                        onChanged: (List<String> values) =>
                            setState(() => _selected = values),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        key: const ValueKey<String>('interested-in-gate-save'),
                        onPressed: _selected.isEmpty || _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Ver perfiles'),
                      ),
                      if (widget.onChangeMode != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        TextButton(
                          key: const ValueKey<String>(
                              'interested-in-gate-change-mode'),
                          onPressed: _saving ? null : widget.onChangeMode,
                          child: const Text('Prefiero cambiar lo que busco'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
