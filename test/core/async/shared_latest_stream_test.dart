import 'dart:async';

import 'package:attra/core/async/shared_latest_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// La campana y la lista de Chats piden su stream en build(): cada repintado
/// del HomeShell reabría sus escuchas de Firestore. shareLatest deja una sola
/// escucha para todos y repite lo último a quien llega tarde.
class _Source {
  int opened = 0;
  int cancelled = 0;
  StreamController<int>? controller;

  Stream<int> open() {
    opened++;
    final StreamController<int> c = StreamController<int>(
      onCancel: () => cancelled++,
    );
    controller = c;
    return c.stream;
  }
}

void main() {
  test('dos oyentes comparten UNA suscripción a la fuente', () async {
    final _Source source = _Source();
    final Stream<int> shared = shareLatest(source.open);
    final List<int> a = <int>[];
    final List<int> b = <int>[];

    final StreamSubscription<int> subA = shared.listen(a.add);
    final StreamSubscription<int> subB = shared.listen(b.add);
    source.controller!.add(1);
    await pumpEventQueue();

    expect(source.opened, 1);
    expect(a, <int>[1]);
    expect(b, <int>[1]);
    await subA.cancel();
    await subB.cancel();
  });

  test('quien llega tarde recibe al momento lo último conocido', () async {
    final _Source source = _Source();
    final Stream<int> shared = shareLatest(source.open);
    final StreamSubscription<int> first = shared.listen((_) {});
    source.controller!
      ..add(1)
      ..add(2);
    await pumpEventQueue();

    final List<int> tardio = <int>[];
    final StreamSubscription<int> second = shared.listen(tardio.add);
    await pumpEventQueue();

    expect(tardio, <int>[2]);
    expect(source.opened, 1);
    await first.cancel();
    await second.cancel();
  });

  test(
      'el último en irse cierra la fuente; al volver se reabre sin repetir un '
      'valor viejo', () async {
    final _Source source = _Source();
    final Stream<int> shared = shareLatest(source.open);
    final StreamSubscription<int> sub = shared.listen((_) {});
    source.controller!.add(7);
    await pumpEventQueue();
    await sub.cancel();

    expect(source.cancelled, 1);

    final List<int> again = <int>[];
    final StreamSubscription<int> sub2 = shared.listen(again.add);
    await pumpEventQueue();
    expect(source.opened, 2);
    expect(again, isEmpty, reason: 'el 7 era de la consulta anterior');

    source.controller!.add(8);
    await pumpEventQueue();
    expect(again, <int>[8]);
    await sub2.cancel();
  });

  test('los errores llegan a todos y, si la fuente termina, se reabre',
      () async {
    final _Source source = _Source();
    final Stream<int> shared = shareLatest(source.open);
    final List<Object> errors = <Object>[];
    bool done = false;
    shared.listen((_) {}, onError: errors.add, onDone: () => done = true);

    source.controller!.addError(StateError('permiso'));
    await source.controller!.close();
    await pumpEventQueue();

    expect(errors, hasLength(1));
    expect(done, isTrue);

    final List<int> next = <int>[];
    final StreamSubscription<int> sub = shared.listen(next.add);
    source.controller!.add(3);
    await pumpEventQueue();
    expect(source.opened, 2);
    expect(next, <int>[3]);
    await sub.cancel();
  });
}
