import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../data/notification_service.dart';
import '../domain/app_notification.dart';

/// Color corporativo por acento (mapea el dominio puro a AppColors).
Color accentColor(NotifAccent a) {
  switch (a) {
    case NotifAccent.desire:
      return AppColors.attraRed;
    case NotifAccent.match:
      return AppColors.coral;
    case NotifAccent.premium:
      return AppColors.gold;
    case NotifAccent.calm:
      return AppColors.success;
    case NotifAccent.safety:
      return AppColors.nightBlue;
  }
}

/// Bandeja de notificaciones: lista elegante con emoji + copy + acento de marca.
/// Al tocar, marca leída y navega a la ruta lógica via [onOpenRoute].
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.service,
    required this.uid,
    required this.onOpenRoute,
  });

  final NotificationService service;
  final String uid;
  final void Function(String route) onOpenRoute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: <Widget>[
          TextButton(
            onPressed: () => service.markAllRead(uid),
            child: const Text('Marcar leídas'),
          ),
        ],
      ),
      body: AttraGradientBackground(
        child: StreamBuilder<List<AppNotification>>(
          stream: service.watch(uid),
          builder: (BuildContext context,
              AsyncSnapshot<List<AppNotification>> snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.attraRed));
            }
            final List<AppNotification> items = snap.data ?? <AppNotification>[];
            if (items.isEmpty) return const _Empty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int i) => _NotifTile(
                n: items[i],
                onTap: () {
                  service.markRead(uid, items[i].id);
                  onOpenRoute(items[i].route);
                },
                onDismiss: () => service.delete(uid, items[i].id),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile(
      {required this.n, required this.onTap, required this.onDismiss});

  final AppNotification n;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = accentColor(n.accent);
    return Dismissible(
      key: ValueKey<String>(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.textMuted),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: n.read
                  ? AppColors.surface
                  : accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                  color: n.read
                      ? AppColors.surfaceLine
                      : accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.18),
                  ),
                  child: Text(n.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(n.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary)),
                      if (n.createdAt != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(_timeAgo(n.createdAt!),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                ),
                if (!n.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime d) {
    final Duration diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return '${d.day}/${d.month}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.notifications_none_rounded,
                size: 56, color: AppColors.attraRed),
            const SizedBox(height: 16),
            Text('Sin novedades por ahora',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('Cuando alguien te dé like o te escriba, lo verás aquí 🔔',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Campana con badge de no leídas (para la AppBar).
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.service,
    required this.uid,
    required this.onTap,
  });

  final NotificationService service;
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: service.watchUnreadCount(uid),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        final int n = snap.data ?? 0;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            IconButton(
              tooltip: 'Notificaciones',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: onTap,
            ),
            if (n > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: AppColors.attraRed,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.black, width: 1.5),
                  ),
                  child: Text(
                    n > 9 ? '9+' : '$n',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
