import 'package:flutter/material.dart';

import '../../../widgets/attra_image.dart';

/// Que accion eligio el usuario en el sheet de respuesta a una foto.
enum PhotoResponseKind { like, attra }

class PhotoResponseResult {
  const PhotoResponseResult({required this.kind, this.comment});
  final PhotoResponseKind kind;
  final String? comment;
}

/// Bottom sheet "Responde a esta foto": preview + comentario opcional + enviar
/// Like o Attra. Devuelve [PhotoResponseResult] o null si se cancela.
class PhotoResponseSheet extends StatefulWidget {
  const PhotoResponseSheet({
    super.key,
    required this.name,
    required this.photoUrl,
    required this.attraBalance,
    this.canComment = false,
  });

  final String name;
  final String photoUrl;
  final int attraBalance;

  /// Si es false, comentar (función Plus) queda bloqueado; se puede enviar
  /// Like/Attra sin texto.
  final bool canComment;

  static Future<PhotoResponseResult?> show(
    BuildContext context, {
    required String name,
    required String photoUrl,
    required int attraBalance,
    bool canComment = false,
  }) {
    return showModalBottomSheet<PhotoResponseResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PhotoResponseSheet(
        name: name,
        photoUrl: photoUrl,
        attraBalance: attraBalance,
        canComment: canComment,
      ),
    );
  }

  @override
  State<PhotoResponseSheet> createState() => _PhotoResponseSheetState();
}

class _PhotoResponseSheetState extends State<PhotoResponseSheet> {
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
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Responde a esta foto', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.canComment
                ? 'Escribe algo breve para destacar (opcional).'
                : 'Comentar es una función Plus. Puedes enviar Like o Attra a esta foto.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 96,
                  child: AttraImage(url: widget.photoUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: widget.canComment
                    ? TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 3,
                        maxLength: _maxLength,
                        buildCounter: (_,
                                {required int currentLength,
                                required bool isFocused,
                                int? maxLength}) =>
                            null,
                        decoration: InputDecoration(
                          hintText: 'Escribe un comentario…',
                          border: const OutlineInputBorder(),
                          errorText:
                              tooLong ? 'Comentario demasiado largo' : null,
                        ),
                      )
                    : const _LockedCommentNote(),
              ),
            ],
          ),
          if (widget.canComment)
            Align(
              alignment: Alignment.centerRight,
              child: Text('$remaining',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: tooLong
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: tooLong ? null : () => _send(PhotoResponseKind.like),
            icon: const Icon(Icons.favorite),
            label: Text(_comment == null
                ? 'Enviar Like'
                : 'Enviar Like con comentario'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: tooLong && hasAttras
                ? null
                : () {
                    if (!hasAttras) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'No tienes Attras suficientes. Compra de Attras proximamente.'),
                        ),
                      );
                      return;
                    }
                    _send(PhotoResponseKind.attra);
                  },
            icon: const Icon(Icons.star),
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

/// Aviso de comentario bloqueado (función Plus) en lugar del campo de texto.
class _LockedCommentNote extends StatelessWidget {
  const _LockedCommentNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PlusChip(),
                const SizedBox(height: 4),
                Text(
                  'Añade un comentario con Attra Plus',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusChip extends StatelessWidget {
  const _PlusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFB8860B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('Plus',
          style: TextStyle(
              color: Color(0xFFB8860B),
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }
}
