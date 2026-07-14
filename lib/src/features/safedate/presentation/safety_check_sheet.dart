import 'package:flutter/material.dart';

import '../data/safedate_service.dart';
import '../domain/conversation_risk.dart';

/// Revisión de seguridad de una conversación (Fase 6). Pide consentimiento
/// explícito, llama al backend (ventana pequeña + PII redactada) y muestra
/// consejos suaves. Preventivo: nunca es un veredicto sobre la persona y el
/// usuario mantiene el control. No informa al match de nada.
class SafetyCheckSheet {
  /// Orquesta consentimiento → análisis → resultado. Devuelve cuando se cierra.
  static Future<void> run(
    BuildContext context, {
    required SafeDateService service,
    required String chatId,
  }) async {
    final bool consent = await _askConsent(context);
    if (!consent || !context.mounted) return;

    // Análisis con indicador de progreso modal.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    ConversationRiskResult? result;
    String? error;
    try {
      result = await service.analyzeConversationRisk(chatId, consent: true);
    } on SafeDateException catch (e) {
      error = e.message;
    }
    if (context.mounted) Navigator.of(context).pop(); // cierra el loader
    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await _showResult(context, result!);
  }

  static Future<bool> _askConsent(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Revisar seguridad'),
        content: const Text(
          'Analizaremos de forma privada los últimos mensajes de esta '
          'conversación para darte consejos de seguridad. No guardamos el texto '
          'ni informamos a la otra persona. ¿Continuar?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Aceptar y revisar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static Future<void> _showResult(
      BuildContext context, ConversationRiskResult r) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        final Color accent = r.tier == 'urgent'
            ? theme.colorScheme.error
            : r.tier == 'warning'
                ? Colors.orange
                : theme.colorScheme.primary;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    r.hasSignals
                        ? Icons.shield_outlined
                        : Icons.verified_user_outlined,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Revisión de seguridad',
                        style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(r.intro, style: theme.textTheme.bodyMedium),
              if (r.tips.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                for (final String tip in r.tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.chevron_right, size: 18, color: accent),
                        const SizedBox(width: 6),
                        Expanded(child: Text(tip)),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Esto son recordatorios de seguridad, no un juicio sobre la otra '
                'persona. Tú decides qué hacer.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
