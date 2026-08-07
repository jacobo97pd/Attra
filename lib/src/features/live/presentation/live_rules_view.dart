import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/live_constants.dart';
import '../domain/live_rules.dart';

/// Pantalla de normas del directo. Se muestra ANTES de pedir cámara y micro.
///
/// PORQUÉ antes y no después: la app ya fue rechazada por la guideline 1.2
/// (contenido generado por usuarios) y este es exactamente ese terreno —vídeo
/// en directo con un desconocido—. El usuario tiene que saber qué está
/// prohibido, que sus fotogramas se analizan automáticamente y qué le pasa si
/// incumple ANTES de que se encienda su cámara; enseñarlo cuando ya está
/// emitiendo no informa de nada, solo justifica a posteriori.
///
/// No hay forma de saltarlo: el único camino a la cámara es [onAccept].
class LiveRulesView extends StatelessWidget {
  const LiveRulesView({
    super.key,
    required this.onAccept,
    required this.onCancel,
  });

  final VoidCallback onAccept;
  final VoidCallback onCancel;

  static IconData _iconFor(LiveRuleId id) {
    switch (id) {
      case LiveRuleId.nudity:
        return Icons.do_not_touch_outlined;
      case LiveRuleId.automatedReview:
        return Icons.policy_outlined;
      case LiveRuleId.sanctions:
        return Icons.gavel_rounded;
      case LiveRuleId.reporting:
        return Icons.flag_outlined;
      case LiveRuleId.privacy:
        return Icons.lock_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int minutes = LiveConstants.sessionMax.inMinutes;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            children: <Widget>[
              const Icon(Icons.sensors_rounded, size: 48, color: Colors.white),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Antes de entrar al directo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vas a hablar por vídeo $minutes minutos con una persona '
                'desconocida. Léelo entero: son 20 segundos y evitan un mal '
                'rato.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final LiveRule rule in LiveRules.all) ...<Widget>[
                _RuleTile(icon: _iconFor(rule.id), rule: rule),
                const SizedBox(height: AppSpacing.lg),
              ],
              // Requisito de edad: aquí se ve a desconocidos en directo, así que
              // se recuerda donde importa y no solo en el registro.
              Text(
                'Solo para mayores de 18 años. Si ves a alguien que parece '
                'menor de edad, denúncialo: lo revisamos antes de 24 horas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            children: <Widget>[
              // El texto del botón dice explícitamente lo que ocurre a
              // continuación: el sistema pedirá cámara y micrófono. Un "Aceptar"
              // a secas deja al usuario sin saber qué acaba de autorizar.
              AttraPrimaryButton(
                key: const ValueKey<String>('live-rules-accept'),
                label: 'Acepto las normas',
                onPressed: onAccept,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Al continuar te pediremos permiso de cámara y micrófono.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AttraGhostButton(
                key: const ValueKey<String>('live-rules-cancel'),
                label: 'Ahora no',
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.icon, required this.rule});

  final IconData icon;
  final LiveRule rule;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                rule.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                rule.body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
