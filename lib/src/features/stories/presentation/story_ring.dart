import 'package:flutter/material.dart';

/// Aro de story: avatar con anillo degradado si hay story viva. Si [isAdd]
/// muestra un "+" para crear.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.name,
    required this.onTap,
    this.imageUrl = '',
    this.hasLiveStory = false,
    this.isAdd = false,
    this.size = 64,
  });

  final String name;
  final String imageUrl;
  final bool hasLiveStory;
  final bool isAdd;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: SizedBox(
        width: size + 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasLiveStory
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFFB8860B),
                          Color(0xFF1D6A96),
                        ],
                      )
                    : null,
                color: hasLiveStory ? null : theme.colorScheme.outlineVariant,
              ),
              child: Stack(
                children: <Widget>[
                  CircleAvatar(
                    radius: size / 2,
                    backgroundColor: const Color(0xFFE0E0E0),
                    backgroundImage:
                        imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                    child: imageUrl.isEmpty
                        ? Text(initial,
                            style: const TextStyle(fontWeight: FontWeight.bold))
                        : null,
                  ),
                  if (isAdd)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.add,
                            size: 15, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isAdd ? 'Tu story' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
