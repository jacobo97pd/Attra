import 'like.dart';

/// Orden y filtro defensivo de la bandeja de likes enviados.
class SentLikeOrdering {
  const SentLikeOrdering._();

  static List<Like> newestPending(Iterable<Like> likes) {
    final List<Like> pending = likes
        .where((Like like) => like.status == LikeStatus.active)
        .toList(growable: true)
      ..sort(
        (Like a, Like b) =>
            _millis(b.createdAt).compareTo(_millis(a.createdAt)),
      );
    return pending;
  }

  static int _millis(DateTime? date) => date?.millisecondsSinceEpoch ?? 0;
}
