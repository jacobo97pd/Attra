import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../domain/closure_templates.dart';

/// Resultado de [CloseConversationSheet]: motivo + mensaje a enviar.
typedef ClosureChoice = ({String reason, String message});

/// Bottom sheet de "Cerrar con elegancia" (Attra Clear §3/§15). Muestra las
/// plantillas, permite un mensaje personalizado y confirma antes de enviar.
/// Devuelve `null` si el usuario cancela.
class CloseConversationSheet extends StatefulWidget {
  const CloseConversationSheet({super.key, required this.otherName});

  final String otherName;

  static Future<ClosureChoice?> show(
    BuildContext context, {
    required String otherName,
  }) {
    return showModalBottomSheet<ClosureChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CloseConversationSheet(otherName: otherName),
    );
  }

  @override
  State<CloseConversationSheet> createState() => _CloseConversationSheetState();
}

class _CloseConversationSheetState extends State<CloseConversationSheet> {
  ClosureTemplate _selected = kClosureTemplates.first;
  final TextEditingController _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _messageToSend =>
      _selected.isCustom ? _custom.text.trim() : _selected.message;

  bool get _canSend => _messageToSend.isNotEmpty;

  void _confirm() {
    if (!_canSend) return;
    Navigator.of(context).pop<ClosureChoice>(
      (reason: _selected.reason, message: _messageToSend),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                Text('Cerrar con elegancia',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Cerrar con elegancia evita dejar a la otra persona en el aire. '
                  'Se enviará como último mensaje y la conversación se cerrará.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 16),
                ...kClosureTemplates.map(_buildTile),
                if (_selected.isCustom) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _custom,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Escribe tu mensaje de despedida…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.attraRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _canSend ? _confirm : null,
                    child: const Text(
                      'Enviar y cerrar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Ahora no'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(ClosureTemplate t) {
    final bool selected = t.reason == _selected.reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.attraRed.withValues(alpha: 0.10)
            : context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.attraRed.withValues(alpha: 0.5)
                    : context.colors.surfaceLine,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected
                      ? AppColors.attraRed
                      : context.colors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t.label,
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700)),
                      if (!t.isCustom) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(t.message,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12.5,
                                height: 1.3)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
