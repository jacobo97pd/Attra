import 'package:attra/src/features/match/domain/like.dart';
import 'package:attra/src/features/match/domain/received_like_priority.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceivedLikePriority', () {
    test('ordena Attra > Pro > Plus > normal', () {
      final List<Like> sorted = ReceivedLikePriority.sortAndFilter(
        likes: <Like>[
          _like('normal'),
          _like('plus', senderIsPlus: true),
          _like('attra', type: LikeType.attra),
          _like('pro', senderIsPro: true),
        ],
      );

      expect(sorted.map((Like l) => l.fromUid),
          <String>['attra', 'pro', 'plus', 'normal']);
    });

    test('un like normal reciente no supera un Attra antiguo', () {
      final List<Like> sorted = ReceivedLikePriority.sortAndFilter(
        likes: <Like>[
          _like('normal_recent', createdAt: DateTime.utc(2026, 1, 2)),
          _like(
            'old_attra',
            type: LikeType.attra,
            createdAt: DateTime.utc(2025, 1, 2),
          ),
        ],
      );

      expect(sorted.map((Like l) => l.fromUid),
          <String>['old_attra', 'normal_recent']);
    });

    test('dentro del mismo grupo usa compatibilidad, actividad y fecha', () {
      final List<Like> sorted = ReceivedLikePriority.sortAndFilter(
        likes: <Like>[
          _like(
            'recent_low_compat',
            senderIsPro: true,
            compatibilityScore: 0.20,
            senderActivityScore: 1,
            createdAt: DateTime.utc(2026, 1, 3),
          ),
          _like(
            'best_compat',
            senderIsPro: true,
            compatibilityScore: 0.92,
            senderActivityScore: 0,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
          _like(
            'same_compat_more_active',
            senderIsPro: true,
            compatibilityScore: 0.20,
            senderActivityScore: 8,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      expect(sorted.map((Like l) => l.fromUid), <String>[
        'best_compat',
        'same_compat_more_active',
        'recent_low_compat',
      ]);
    });

    test('usuario bloqueado no aparece', () {
      final List<Like> sorted = ReceivedLikePriority.sortAndFilter(
        likes: <Like>[_like('blocked'), _like('visible')],
        blockedUids: <String>{'blocked'},
      );

      expect(sorted.map((Like l) => l.fromUid), <String>['visible']);
    });

    test('usuario con match ya creado no aparece', () {
      final List<Like> sorted = ReceivedLikePriority.sortAndFilter(
        likes: <Like>[_like('matched'), _like('visible')],
        matchedUids: <String>{'matched'},
      );

      expect(sorted.map((Like l) => l.fromUid), <String>['visible']);
    });
  });
}

Like _like(
  String fromUid, {
  LikeType type = LikeType.like,
  bool senderIsPlus = false,
  bool senderIsPro = false,
  double? compatibilityScore,
  double? senderActivityScore,
  DateTime? createdAt,
}) {
  return Like(
    fromUid: fromUid,
    toUid: 'me',
    type: type,
    status: LikeStatus.active,
    senderIsPlus: senderIsPlus,
    senderIsPro: senderIsPro,
    compatibilityScore: compatibilityScore,
    senderActivityScore: senderActivityScore,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );
}
