import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Avatar de grupo: muestra la foto del grupo si existe, o un icono rojo tintado
/// de respaldo. Sirve como cuadrado redondeado (tarjetas) o círculo (chats).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.photoUrl,
    this.fallbackIcon = Icons.groups_rounded,
    this.size = 52,
    this.circle = false,
    this.radius = 15,
  });

  final String photoUrl;
  final IconData fallbackIcon;
  final double size;
  final bool circle;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br =
        BorderRadius.circular(circle ? size / 2 : radius);
    if (photoUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.attraRed.withValues(alpha: 0.15),
          borderRadius: br,
        ),
        child: Icon(fallbackIcon, color: AppColors.attraRed, size: size * 0.46),
      );
    }
    return ClipRRect(
      borderRadius: br,
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          color: AppColors.surfaceHigh,
        ),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.attraRed.withValues(alpha: 0.15),
            borderRadius: br,
          ),
          child: Icon(fallbackIcon,
              color: AppColors.attraRed, size: size * 0.46),
        ),
      ),
    );
  }
}
