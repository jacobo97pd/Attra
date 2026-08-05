import 'package:attra/src/features/match/domain/like.dart';
import 'package:attra/src/features/match/domain/sent_like_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SentLikeOrdering', () {
    test(
        'solo conserva likes pendientes y ordena del más reciente al más viejo',
        () {
      final List<Like> result = SentLikeOrdering.newestPending(<Like>[
        _like('old', createdAt: DateTime.utc(2026, 1, 1)),
        _like(
          'matched',
          status: LikeStatus.matched,
          createdAt: DateTime.utc(2026, 1, 4),
        ),
        _like('new', createdAt: DateTime.utc(2026, 1, 3)),
        _like('middle', createdAt: DateTime.utc(2026, 1, 2)),
      ]);

      expect(
        result.map((Like like) => like.toUid),
        <String>['new', 'middle', 'old'],
      );
    });

    test('fecha ausente queda al final', () {
      final List<Like> result = SentLikeOrdering.newestPending(<Like>[
        _like('without_date', createdAt: null),
        _like('dated', createdAt: DateTime.utc(2026, 1, 1)),
      ]);

      expect(
        result.map((Like like) => like.toUid),
        <String>['dated', 'without_date'],
      );
    });
  });
}

Like _like(
  String toUid, {
  LikeStatus status = LikeStatus.active,
  DateTime? createdAt,
}) {
  return Like(
    fromUid: 'me',
    toUid: toUid,
    type: LikeType.like,
    status: status,
    createdAt: createdAt,
  );
}
