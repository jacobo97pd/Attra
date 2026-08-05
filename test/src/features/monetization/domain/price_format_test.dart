import 'package:attra/src/features/monetization/domain/price_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('repriceLike conserva el formato de la tienda', () {
    test('caso real de producción: dólares con punto decimal', () {
      // En dispositivo se vio "$179.99 / año" junto a "Equivale a 15,00 $ / mes".
      // El equivalente mensual DEBE salir en el mismo formato que el anual.
      expect(repriceLike(r'$179.99', 179.99 / 12), r'$15.00');
    });

    test('euros con coma decimal y símbolo detrás', () {
      expect(repriceLike('179,99 €', 179.99 / 12), '15,00 €');
      expect(repriceLike('99,99 €', 99.99 / 12), '8,33 €');
    });

    test('moneda sin decimales conserva que no los tiene', () {
      // JPY: "¥19,800" -> la coma es separador de MILES, no decimal.
      expect(repriceLike('¥19,800', 19800 / 12), '¥1,650');
    });

    test('separador de miles europeo (punto) con decimales (coma)', () {
      expect(repriceLike('1.199,99 €', 1199.99 / 12), '100,00 €');
    });

    test('separador de miles anglosajón (coma) con decimales (punto)', () {
      expect(repriceLike(r'$1,199.88', 1199.88 / 12), r'$99.99');
    });

    test('código de moneda de tres letras detrás', () {
      expect(repriceLike('179.99 USD', 179.99 / 12), '15.00 USD');
    });

    test('espacio duro como separador de miles (fr-FR)', () {
      expect(repriceLike('1 199,99 €', 1199.99 / 12), '100,00 €');
    });

    test('devuelve null si no hay número que sustituir', () {
      expect(repriceLike('Gratis', 5), isNull);
      expect(repriceLike('', 5), isNull);
    });

    test('devuelve null con importes no válidos', () {
      expect(repriceLike(r'$179.99', double.nan), isNull);
      expect(repriceLike(r'$179.99', double.infinity), isNull);
      expect(repriceLike(r'$179.99', -1), isNull);
    });

    test('redondea a los decimales que use la tienda', () {
      // 100/12 = 8,3333... -> dos decimales como el original.
      expect(repriceLike('100,00 €', 100 / 12), '8,33 €');
      // Sin decimales en el original -> sin decimales en el resultado.
      expect(repriceLike('¥100', 100 / 12), '¥8');
    });
  });

  group('monthlyEquivalentOf', () {
    test('divide entre 12 y conserva formato', () {
      expect(monthlyEquivalentOf(r'$179.99', 179.99), r'$15.00');
      expect(monthlyEquivalentOf('99,99 €', 99.99), '8,33 €');
    });

    test('null si el precio anual no es utilizable', () {
      expect(monthlyEquivalentOf(r'$0.00', 0), isNull);
      expect(monthlyEquivalentOf(r'$179.99', -5), isNull);
      expect(monthlyEquivalentOf(r'$179.99', double.nan), isNull);
    });
  });
}
