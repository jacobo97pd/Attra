import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_editorial.dart';
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
    required this.kind,
    required this.name,
    required this.photoUrl,
    required this.attraBalance,
    this.canComment = false,
  });

  final PhotoResponseKind kind;
  final String name;
  final String photoUrl;
  final int attraBalance;

  /// Si es false, comentar (función Plus) queda bloqueado; se puede enviar
  /// Like/Attra sin texto.
  final bool canComment;

  static Future<PhotoResponseResult?> show(
    BuildContext context, {
    required PhotoResponseKind kind,
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
        kind: kind,
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

  void _send() {
    Navigator.of(context).pop(
      PhotoResponseResult(kind: widget.kind, comment: _comment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int remaining = _maxLength - _controller.text.characters.length;
    final bool tooLong = remaining < 0;
    final bool hasAttras = widget.attraBalance > 0;
    final bool isAttra = widget.kind == PhotoResponseKind.attra;

    final Widget comment = widget.canComment
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
              errorText: tooLong ? 'Comentario demasiado largo' : null,
            ),
          )
        : const _LockedCommentNote();
    final Widget photo = Semantics(
      image: true,
      label: 'Foto de ${widget.name}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: SizedBox(
          width: 96,
          height: 128,
          child: AttraImage(url: widget.photoUrl),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.pageInset(context),
          right: AppSpacing.pageInset(context),
          top: AppSpacing.xs,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: AttraContentFrame(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AttraSectionHeading(
                title: isAttra
                    ? 'Envía un Attra a esta foto'
                    : 'Responde a esta foto',
                subtitle: widget.canComment
                    ? 'Escribe algo breve para destacar (opcional).'
                    : 'Puedes enviarlo sin texto. El comentario es opcional con Plus.',
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool stack = constraints.maxWidth < 360 ||
                      MediaQuery.textScalerOf(context).scale(17) > 24;
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        photo,
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(width: double.infinity, child: comment),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      photo,
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(child: comment),
                    ],
                  );
                },
              ),
              if (widget.canComment)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('$remaining',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: tooLong
                              ? theme.colorScheme.error
                              : context.colors.textMuted)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey<String>(
                    isAttra
                        ? 'photo-response-submit-attra'
                        : 'photo-response-submit-like',
                  ),
                  style: isAttra
                      ? FilledButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.black,
                        )
                      : null,
                  onPressed: tooLong || (isAttra && !hasAttras) ? null : _send,
                  icon: isAttra
                      ? const Text(
                          'A',
                          style: TextStyle(
                            fontSize: 20,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : const Icon(Icons.favorite_border_rounded),
                  label: Text(
                    isAttra
                        ? 'Enviar Attra · ${widget.attraBalance}'
                        : _comment == null
                            ? 'Enviar Like'
                            : 'Enviar Like con comentario',
                  ),
                ),
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
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline,
              size: 20, color: context.colors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(
            'Comentario con Plus',
            style: theme.textTheme.bodyMedium,
          )),
        ],
      ),
    );
  }
}
