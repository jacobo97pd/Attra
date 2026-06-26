import 'package:flutter_test/flutter_test.dart';
import 'package:attra/src/features/feed/domain/funnel_metrics.dart';

void main() {
  group('FunnelMetrics.rates', () {
    test('calcula las tasas básicas', () {
      const FunnelCounts c = FunnelCounts(
        likes: 60,
        attras: 10,
        nopes: 30,
        matches: 14,
        conversationsStarted: 7,
        firstMessages: 10,
        replies: 6,
        gamesStarted: 8,
        gamesCompleted: 5,
        datesProposed: 4,
        datesAccepted: 2,
        newUsers: 20,
        newUsersWithMinExposure: 18,
      );
      final FunnelRates r = FunnelMetrics.rates(c);
      // likes+attras=70 de 100 decisiones.
      expect(r.likeRate, closeTo(0.70, 1e-9));
      // matches 14 de 70 likes/attras.
      expect(r.matchRate, closeTo(0.20, 1e-9));
      expect(r.conversationStartRate, closeTo(0.5, 1e-9));
      expect(r.replyRate, closeTo(0.6, 1e-9));
      expect(r.gameCompletionRate, closeTo(0.625, 1e-9));
      expect(r.dateProposalRate, closeTo(14 / 70 == 0.2 ? 4 / 14 : 4 / 14, 1e-9));
      expect(r.dateAcceptanceRate, closeTo(0.5, 1e-9));
      expect(r.newUserMinExposureRate, closeTo(0.9, 1e-9));
    });

    test('sin denominador => 0 (no NaN)', () {
      const FunnelCounts c = FunnelCounts();
      final FunnelRates r = FunnelMetrics.rates(c);
      for (final double v in r.toMap().values) {
        expect(v, 0.0);
      }
    });

    test('todas las tasas quedan en [0,1]', () {
      const FunnelCounts c = FunnelCounts(
        likes: 5,
        matches: 50, // más matches que likes (datos sucios) => clamp a 1
        conversationsStarted: 100,
      );
      final FunnelRates r = FunnelMetrics.rates(c);
      for (final double v in r.toMap().values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
