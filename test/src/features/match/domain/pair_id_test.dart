import 'package:attra/src/features/match/domain/pair_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pairId', () {
    test('es simetrico: pairId(a,b) == pairId(b,a)', () {
      expect(pairId('alice', 'bob'), pairId('bob', 'alice'));
    });

    test('ordena los uids de forma estable', () {
      expect(pairId('bob', 'alice'), 'alice_bob');
      expect(pairId('alice', 'bob'), 'alice_bob');
    });

    test('mismo uid en ambos lados', () {
      expect(pairId('x', 'x'), 'x_x');
    });
  });

  group('directedId', () {
    test('NO es simetrico: conserva la direccion from->to', () {
      expect(directedId('a', 'b'), 'a_b');
      expect(directedId('b', 'a'), 'b_a');
      expect(directedId('a', 'b') == directedId('b', 'a'), isFalse);
    });
  });
}
