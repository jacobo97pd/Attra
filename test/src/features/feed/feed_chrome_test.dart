import 'package:attra/src/features/feed/domain/feed_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool? paso(
    FeedChromeTracker t, {
    required double pixels,
    required double delta,
    double max = 1000,
  }) =>
      t.update(pixels: pixels, minExtent: 0, maxExtent: max, delta: delta);

  test('arriba del todo la cabecera se ve, venga de donde venga', () {
    final FeedChromeTracker t = FeedChromeTracker();
    expect(paso(t, pixels: 400, delta: 40), isTrue);
    expect(paso(t, pixels: 4, delta: 30), isFalse);
    // Rebote por encima del principio (iOS): también arriba.
    expect(paso(t, pixels: -20, delta: 10), isFalse);
  });

  test('un arrastre lento también pliega: se acumula el recorrido', () {
    final FeedChromeTracker t = FeedChromeTracker();
    bool? ultimo;
    double pixels = 20;
    for (int i = 0; i < 6; i++) {
      pixels += 2;
      ultimo = paso(t, pixels: pixels, delta: 2);
    }
    expect(ultimo, isTrue,
        reason: 'mirando cada frame suelto (2 px) no se plegaría nunca');
  });

  test('un temblor por debajo del umbral no cambia nada', () {
    final FeedChromeTracker t = FeedChromeTracker();
    expect(paso(t, pixels: 300, delta: 5), isNull);
    expect(paso(t, pixels: 297, delta: -3), isNull);
    expect(paso(t, pixels: 302, delta: 5), isNull);
  });

  test('cambiar de dirección empieza a contar de cero', () {
    final FeedChromeTracker t = FeedChromeTracker();
    expect(paso(t, pixels: 300, delta: 11), isNull);
    // Si no se reiniciara, 11 - 4 dejaría 7 "hacia abajo" y subir 8 no bastaría
    // para nada; al revés, los 11 ya no deben contar para bajar.
    expect(paso(t, pixels: 296, delta: -4), isNull);
    expect(paso(t, pixels: 286, delta: -10), isFalse);
  });

  test('el rebote al pasarse del final no devuelve la cabecera', () {
    final FeedChromeTracker t = FeedChromeTracker();
    expect(paso(t, pixels: 900, delta: 60), isTrue);
    // El contenido vuelve atrás solo desde más allá del final.
    expect(paso(t, pixels: 1030, delta: -20), isNull);
    expect(paso(t, pixels: 1000, delta: -30), isNull);
    // Subir de verdad desde el final sí la devuelve.
    expect(paso(t, pixels: 980, delta: -20), isFalse);
  });

  test('reset olvida lo acumulado de la ficha anterior', () {
    final FeedChromeTracker t = FeedChromeTracker();
    expect(paso(t, pixels: 300, delta: 10), isNull);
    t.reset();
    expect(paso(t, pixels: 305, delta: 5), isNull,
        reason: '10 + 5 habría plegado con lo arrastrado de otra ficha');
  });
}
