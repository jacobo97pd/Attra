import 'like.dart';

class ReceivedLikePriority {
  const ReceivedLikePriority._();

  static List<Like> sortAndFilter({
    required Iterable<Like> likes,
    Set<String> blockedUids = const <String>{},
    Set<String> matchedUids = const <String>{},
  }) {
    final List<Like> out = likes
        .where((Like like) => like.status == LikeStatus.active)
        .where((Like like) => !blockedUids.contains(like.fromUid))
        .where((Like like) => !matchedUids.contains(like.fromUid))
        .toList(growable: true)
      ..sort(compare);
    return out;
  }

  static int compare(Like a, Like b) {
    final int bucket = _bucket(a).compareTo(_bucket(b));
    if (bucket != 0) return bucket;

    final int compatibility =
        _compareNullableDesc(a.compatibilityScore, b.compatibilityScore);
    if (compatibility != 0) return compatibility;

    final int activity =
        _compareNullableDesc(_activityValue(a), _activityValue(b));
    if (activity != 0) return activity;

    return _millis(b.createdAt).compareTo(_millis(a.createdAt));
  }

  static int _bucket(Like like) {
    if (like.type.isAttra) return 0;
    if (like.senderIsPro) return 1;
    if (like.senderIsPlus) return 2;
    return 3;
  }

  static double? _activityValue(Like like) {
    final double? score = like.senderActivityScore;
    if (score != null) return score;
    final DateTime? lastActiveAt = like.senderLastActiveAt;
    if (lastActiveAt == null) return null;
    return lastActiveAt.millisecondsSinceEpoch.toDouble();
  }

  static int _compareNullableDesc(double? a, double? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static int _millis(DateTime? d) => d?.millisecondsSinceEpoch ?? 0;
}
