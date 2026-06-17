import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Overlay "Nuevo match". Si el match nacio de un comentario a una foto,
/// muestra la miniatura y el comentario de apertura. CTA: abrir chat.
Future<void> showMatchCreatedDialog(
  BuildContext context, {
  required String name,
  required String photoUrl,
  required bool hasAttra,
  String? originComment,
  String? originPhotoUrl,
  required VoidCallback onOpenChat,
  VoidCallback? onPlaySpark,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => _MatchCreatedDialog(
      name: name,
      photoUrl: photoUrl,
      hasAttra: hasAttra,
      originComment: originComment,
      originPhotoUrl: originPhotoUrl,
      onOpenChat: onOpenChat,
      onPlaySpark: onPlaySpark,
    ),
  );
}

class _MatchCreatedDialog extends StatelessWidget {
  const _MatchCreatedDialog({
    required this.name,
    required this.photoUrl,
    required this.hasAttra,
    required this.originComment,
    required this.originPhotoUrl,
    required this.onOpenChat,
    this.onPlaySpark,
  });

  final String name;
  final String photoUrl;
  final bool hasAttra;
  final String? originComment;
  final String? originPhotoUrl;
  final VoidCallback onOpenChat;
  final VoidCallback? onPlaySpark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool fromPhoto =
        (originComment != null && originComment!.trim().isNotEmpty) ||
            (originPhotoUrl != null && originPhotoUrl!.isNotEmpty);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Halo con el gradiente emocional de match (deseo → emoción → premio).
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: AppColors.match,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.wineRed.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(hasAttra ? Icons.star_rounded : Icons.favorite_rounded,
                  size: 44, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            Text('¡Nuevo match!',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              hasAttra ? 'Tienes un nuevo match destacado' : 'Habéis conectado',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFFE0E0E0),
              backgroundImage:
                  photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32))
                  : null,
            ),
            const SizedBox(height: 10),
            Text(name, style: theme.textTheme.titleMedium),
            if (fromPhoto) ...<Widget>[
              const SizedBox(height: 16),
              _OriginCard(
                comment: originComment,
                photoUrl: originPhotoUrl,
              ),
            ],
            if (onPlaySpark != null) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                '¿Queréis jugar 5 minutos para romper el hielo?',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onPlaySpark!();
                  },
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Jugar 5 minutos'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenChat();
                  },
                  child: const Text('Abrir chat'),
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenChat();
                  },
                  child: const Text('Abrir chat'),
                ),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Seguir descubriendo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OriginCard extends StatelessWidget {
  const _OriginCard({required this.comment, required this.photoUrl});

  final String? comment;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (photoUrl != null && photoUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(photoUrl!,
                  width: 44, height: 56, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const _DeletedPhotoThumb()),
            )
          else
            const _DeletedPhotoThumb(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Respondió a tu foto',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
                if (comment != null && comment!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(comment!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletedPhotoThumb extends StatelessWidget {
  const _DeletedPhotoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 56,
      color: const Color(0xFFE0E0E0),
      child: const Icon(Icons.image_not_supported_outlined, size: 20),
    );
  }
}
