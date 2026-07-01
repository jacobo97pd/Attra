import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Acción elegida en el [PendingLimitBottomSheet].
enum PendingLimitAction { viewConversations, closeSome, notNow }

/// Bottom sheet del límite suave de conversaciones pendientes (Attra Clear §2).
/// NO castiga: siempre se puede responder, cerrar, bloquear o reportar. Devuelve
/// la acción elegida (o `null` si se descarta).
class PendingLimitBottomSheet extends StatelessWidget {
  const PendingLimitBottomSheet({super.key, required this.pendingCount});

  final int pendingCount;

  static Future<PendingLimitAction?> show(
    BuildContext context, {
    required int pendingCount,
  }) {
    return showModalBottomSheet<PendingLimitAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PendingLimitBottomSheet(pendingCount: pendingCount),
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
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: <Color>[
                      AppColors.attraRed.withValues(alpha: 0.22),
                      Colors.transparent,
                    ]),
                  ),
                  child: const Icon(Icons.forum_rounded,
                      size: 30, color: AppColors.attraRed),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tienes conversaciones esperando',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Para seguir conociendo gente, responde o cierra algunas '
                'conversaciones pendientes. Así Attra mantiene matches con más '
                'intención.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.textSecondary),
              ),
              const SizedBox(height: 20),
              _PrimaryBtn(
                label: 'Ver conversaciones',
                onTap: () => Navigator.of(context)
                    .pop(PendingLimitAction.viewConversations),
              ),
              const SizedBox(height: 10),
              _SecondaryBtn(
                label: 'Cerrar algunas',
                onTap: () =>
                    Navigator.of(context).pop(PendingLimitAction.closeSome),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(PendingLimitAction.notNow),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.attraRed,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: context.colors.surfaceLine),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}
