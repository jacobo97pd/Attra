import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import 'photo_response_sheet.dart' show PhotoResponseKind, PhotoResponseResult;

/// Bottom sheet "Responde a esta respuesta": muestra el prompt (pregunta +
/// respuesta) del otro perfil y permite enviar Like o Attra con comentario
/// opcional (el comentario es función Plus, igual que en fotos).
/// Devuelve [PhotoResponseResult] o null si se cancela.
class PromptResponseSheet extends StatefulWidget {
  const PromptResponseSheet({
    super.key,
    required this.name,
    required this.question,
    required this.answer,
    required this.attraBalance,
    this.canComment = false,
  });

  final String name;
  final String question;
  final String answer;
  final int attraBalance;
  final bool canComment;

  static Future<PhotoResponseResult?> show(
    BuildContext context, {
    required String name,
    required String question,
    required String answer,
    required int attraBalance,
    bool canComment = false,
  }) {
    return showModalBottomSheet<PhotoResponseResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PromptResponseSheet(
        name: name,
        question: question,
        answer: answer,
        attraBalance: attraBalance,
        canComment: canComment,
      ),
    );
  }

  @override
  State<PromptResponseSheet> createState() => _PromptResponseSheetState();
}

class _PromptResponseSheetState extends State<PromptResponseSheet> {
  static const int _maxLength = 180;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _comment {
    final String t = _controller.text.trim();
    return t.isEmpty ? null : t;
  }

  void _send(PhotoResponseKind kind) {
    Navigator.of(context)
        .pop(PhotoResponseResult(kind: kind, comment: _comment));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int remaining = _maxLength - _controller.text.characters.length;
    final bool tooLong = remaining < 0;
    final bool hasAttras = widget.attraBalance > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Responde a ${widget.name}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.canComment
                ? 'Comenta su respuesta para destacar (opcional).'
                : 'Comentar es una función Plus. Puedes enviar Like o Attra.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          AttraCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.question, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(widget.answer,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.canComment) ...<Widget>[
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              maxLength: _maxLength,
              buildCounter: (_,
                      {required int currentLength,
                      required bool isFocused,
                      int? maxLength}) =>
                  Text('$remaining',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: tooLong
                              ? AppColors.danger
                              : context.colors.textMuted)),
              decoration: InputDecoration(
                hintText: 'Escribe un comentario…',
                errorText: tooLong ? 'Comentario demasiado largo' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          FilledButton.icon(
            onPressed: tooLong ? null : () => _send(PhotoResponseKind.like),
            icon: const Icon(Icons.favorite),
            label: Text(_comment == null
                ? 'Enviar Like'
                : 'Enviar Like con comentario'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: tooLong
                ? null
                : () {
                    if (!hasAttras) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('No tienes Attras suficientes.')),
                      );
                      return;
                    }
                    _send(PhotoResponseKind.attra);
                  },
            icon: const Icon(Icons.star, color: AppColors.gold),
            label: Text(hasAttras
                ? 'Enviar Attra · ${widget.attraBalance}'
                : 'Comprar Attras'),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ),
        ],
      ),
    );
  }
}
