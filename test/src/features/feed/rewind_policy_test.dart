import 'package:attra/src/features/feed/domain/rewind_policy.dart';
import 'package:attra/src/features/monetization/domain/premium_feature.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:flutter_test/flutter_test.dart';

/// La regla de los tramos de la marcha atrás, tal y como la pidió el dueño:
/// "Free no puede. Plus puede pero una vez. Y Pro puede todas las que quiera".
///
/// Se ejercita la función REAL ([RewindState]), que es la MISMA que usan el feed
/// y el visor a ciegas. Antes esta regla estaba partida entre `_advance`
/// (guardar uno o todos) y `_onRewind` (permitir o no), las dos dentro del
/// `State` de una pantalla que necesita red, historias y geolocalización para
/// montarse: no había forma de probarla sin reimplementarla, que es como se
/// acaban teniendo tests en verde que no ejecutan producción.
RewindEntry _gesto(String uid, {FeedActionKind kind = FeedActionKind.like}) =>
    RewindEntry(targetUid: uid, kind: kind);

void main() {
  group('El tramo sale de los entitlements de verdad', () {
    // Los booleanos que recibe el feed los calcula `HomeShell` con estas dos
    // llamadas. Si alguien saca `rewind` de la lista de Plus, este test cae.
    RewindTier tierDe(SubscriptionTier tier) {
      final UserEntitlements ent =
          UserEntitlements.forTier(uid: 'u', tier: tier);
      return RewindTier.forPlan(
        canRewind: ent.hasFeature(PremiumFeature.rewind),
        unlimited: tier.atLeast(SubscriptionTier.pro),
      );
    }

    test('Free no tiene la función', () {
      expect(tierDe(SubscriptionTier.free), RewindTier.free);
    });

    test('Plus sí', () {
      expect(tierDe(SubscriptionTier.plus), RewindTier.plus);
    });

    test('Pro, sin límite', () {
      expect(tierDe(SubscriptionTier.pro), RewindTier.pro);
    });
  });

  group('Free no puede', () {
    test('el botón se ve, pero bloqueado', () {
      final RewindState state =
          const RewindState().record(_gesto('a'));
      expect(state.status, RewindStatus.locked);
      expect(state.canUndo, isFalse);
      expect(state.remaining, 0);
      expect(state.pending, isNull);
    });

    test('el mensaje dice qué da CADA plan, no solo "es de pago"', () {
      const RewindState state = RewindState();
      expect(state.lockedMessage, contains('Plus'));
      expect(state.lockedMessage, contains('Pro'));
    });

    test('guarda el gesto igualmente: al comprar, funciona ese mismo', () {
      // Si el historial se vaciara al pasar por el paywall, habría pagado para
      // que el botón le dijera "no hay nada que deshacer".
      final RewindState free = const RewindState().record(_gesto('a'));
      final RewindState plus = free.withTier(RewindTier.plus);
      expect(plus.canUndo, isTrue);
      expect(plus.pending?.targetUid, 'a');
    });
  });

  group('Plus: una', () {
    test('solo se guarda el ÚLTIMO gesto', () {
      final RewindState state = const RewindState(tier: RewindTier.plus)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .record(_gesto('c'));
      expect(state.remaining, 1);
      expect(state.pending?.targetUid, 'c');
    });

    test('deshacer deja el botón sin munición', () {
      final RewindState state =
          const RewindState(tier: RewindTier.plus).record(_gesto('a')).undo();
      expect(state.status, RewindStatus.empty);
      expect(state.canUndo, isFalse);
    });

    test('el siguiente gesto vuelve a activarlo', () {
      // "Una vez" es una vez por gesto, no una por sesión: si fuera por sesión,
      // el primer pase por error se comería la función para siempre.
      final RewindState state = const RewindState(tier: RewindTier.plus)
          .record(_gesto('a'))
          .undo()
          .record(_gesto('b'));
      expect(state.canUndo, isTrue);
      expect(state.pending?.targetUid, 'b');
    });

    test('agotado, el mensaje distingue "ya lo has usado" de "aún no"', () {
      const RewindState virgen = RewindState(tier: RewindTier.plus);
      final RewindState gastado =
          virgen.record(_gesto('a')).undo();
      expect(virgen.emptyMessage, contains('Todavía'));
      expect(gastado.emptyMessage, contains('Ya has deshecho'));
      expect(gastado.hint, 'Ya no queda nada que deshacer');
    });

    test('al deshacer se le dice que el siguiente gesto lo reactiva', () {
      final RewindState state =
          const RewindState(tier: RewindTier.plus).record(_gesto('a')).undo();
      expect(state.doneMessage, contains('siguiente like o pase'));
    });
  });

  group('Pro: todas las que quiera', () {
    test('apila la sesión entera y las deshace en orden inverso', () {
      RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .record(_gesto('c'));
      expect(state.remaining, 3);

      state = state.undo();
      expect(state.pending?.targetUid, 'b');
      state = state.undo();
      expect(state.pending?.targetUid, 'a');
      state = state.undo();
      expect(state.status, RewindStatus.empty);
      expect(state.undo().remaining, 0, reason: 'deshacer de más no revienta');
    });

    test('el contador solo sale con más de uno', () {
      final RewindState uno =
          const RewindState(tier: RewindTier.pro).record(_gesto('a'));
      expect(uno.counterLabel, isNull);
      expect(uno.record(_gesto('b')).counterLabel, '2');
    });

    test('el aviso posterior dice cuántas quedan', () {
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .record(_gesto('c'))
          .undo();
      expect(state.doneMessage, contains('2'));
    });
  });

  group('Deshacer el gesto QUE ES, no el último de la pila', () {
    test('llega otro gesto mientras se deshace: se quita el que se deshizo', () {
      // La llamada al backend tarda y la tarjeta seguía aceptando deslizamientos:
      // quitando "el último" se descartaba el gesto RECIÉN hecho (perfectamente
      // deshacible) y se dejaba en la pila el que el servidor ya había borrado,
      // así que la siguiente pulsación caía sobre un doc inexistente.
      final RewindState durante = const RewindState(tier: RewindTier.pro)
          .record(_gesto('ada')) // se pide deshacer este...
          .record(_gesto('zoe')); // ...y este entra mientras va en camino
      final RewindState tras = durante.undoFor('ada');
      expect(tras.remaining, 1);
      expect(tras.pending?.targetUid, 'zoe');
      expect(tras.usedInSession, isTrue);
    });

    test('deshacer lo que ya no está no gasta nada', () {
      final RewindState state =
          const RewindState(tier: RewindTier.pro).record(_gesto('a'));
      expect(identical(state.undoFor('zzz'), state), isTrue);
      expect(state.undoFor('zzz').usedInSession, isFalse);
    });
  });

  group('Qué NO se puede deshacer', () {
    test('un Attra no se lleva por delante los gestos anteriores', () {
      // `rewind.ts` solo se niega a deshacer el propio Attra: los likes y pases
      // anteriores siguen siendo deshacibles en el servidor. Vaciar el historial
      // entero convertía gastar un consumible de pago en perder la función de
      // pago, y encima lo hacía aunque el Attra acabara fallando por saldo.
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .forget('c'); // el Attra va a 'c'
      expect(state.remaining, 2);
      expect(state.pending?.targetUid, 'b');
    });

    test('vaciar el historial es cosa de la recarga (pool nuevo)', () {
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .clearHistory();
      expect(state.status, RewindStatus.empty);
    });

    test('un match borra ese gesto y deja intactos los demás', () {
      // `rewindFeedAction` contesta `failed-precondition` en cuanto hay match:
      // dejar el botón encendido sería prometer algo que siempre falla.
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .forget('b');
      expect(state.remaining, 1);
      expect(state.pending?.targetUid, 'a');
    });

    test('olvidar a quien no está no cambia nada', () {
      final RewindState state =
          const RewindState(tier: RewindTier.pro).record(_gesto('a'));
      expect(identical(state.forget('zzz'), state), isTrue);
    });

    test('dos gestos a la MISMA persona dejan una sola entrada', () {
      // Puede pasar tras deshacer: reaparece y se vuelve a pasar de ella. El
      // backend solo puede borrar el like/dislike que hay ahora, así que una
      // entrada duplicada sería una marcha atrás que no deshace nada.
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a', kind: FeedActionKind.pass))
          .record(_gesto('b'))
          .record(_gesto('a'));
      expect(state.remaining, 2);
      expect(state.pending?.targetUid, 'a');
      expect(state.pending?.kind, FeedActionKind.like);
    });
  });

  group('El plan cambia con la app abierta', () {
    test('subir a Pro conserva lo guardado', () {
      final RewindState state = const RewindState(tier: RewindTier.plus)
          .record(_gesto('a'))
          .withTier(RewindTier.pro);
      expect(state.remaining, 1);
      expect(state.tier, RewindTier.pro);
    });

    test('caer de Pro a Plus recorta a la MÁS RECIENTE', () {
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .record(_gesto('b'))
          .record(_gesto('c'))
          .withTier(RewindTier.plus);
      expect(state.remaining, 1);
      expect(state.pending?.targetUid, 'c');
    });

    test('caer a Free bloquea aunque hubiera historial', () {
      final RewindState state = const RewindState(tier: RewindTier.pro)
          .record(_gesto('a'))
          .withTier(RewindTier.free);
      expect(state.status, RewindStatus.locked);
      expect(state.remaining, 0);
    });
  });

  group('Lo que ve el usuario en cada tramo', () {
    test('cada estado dice algo distinto: ninguno se queda mudo', () {
      final RewindState libre =
          const RewindState(tier: RewindTier.plus).record(_gesto('a'));
      final Set<String> textos = <String>{
        // Free: bloqueado.
        const RewindState().hint,
        // Plus recién entrado: nada que deshacer todavía.
        const RewindState(tier: RewindTier.plus).hint,
        // Plus con su gesto guardado.
        libre.hint,
        // Plus que ya lo ha gastado.
        libre.undo().hint,
        // Pro con varios apilados: además dice cuántos.
        const RewindState(tier: RewindTier.pro)
            .record(_gesto('a'))
            .record(_gesto('b'))
            .hint,
      };
      expect(textos.length, 5);
      for (final String texto in textos) {
        expect(texto.trim(), isNotEmpty);
      }
    });

    test('lo que se manda al backend es lo que espera `rewindFeedAction`', () {
      expect(FeedActionKind.like.wireName, 'like');
      expect(FeedActionKind.pass.wireName, 'pass');
    });
  });
}
