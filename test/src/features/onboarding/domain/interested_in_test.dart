import 'package:attra/src/features/onboarding/domain/interested_in.dart';
import 'package:attra/src/features/profile/domain/gender_matching.dart';
import 'package:attra/src/features/social/domain/intent_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// C11: quien se registraba en amistad o grupos guardaba
/// `preferences.interestedIn = []` y, al pasarse a citas, nada volvía a
/// pedírselo. Vacío = "quiere a todo el mundo" (GenderMatching), así que un
/// hombre hetero que venía de amistad salía también en el feed de los hombres
/// gays. Ahora el cambio de modo exige elegirlo.
class _Calls {
  final List<String> log = <String>[];
  List<String>? savedInterest;
  IntentMode? savedMode;
}

Future<IntentSwitchOutcome> _switch(
  _Calls calls, {
  required IntentMode from,
  required IntentMode to,
  List<String> interestedIn = const <String>[],
  List<String>? answer,
}) {
  return switchIntentModeWithInterest(
    current: from,
    chosen: to,
    interestedIn: interestedIn,
    askInterestedIn: () async {
      calls.log.add('ask');
      return answer;
    },
    saveInterestedIn: (List<String> values) async {
      calls.log.add('saveInterest');
      calls.savedInterest = values;
    },
    saveMode: (IntentMode mode) async {
      calls.log.add('saveMode');
      calls.savedMode = mode;
    },
  );
}

void main() {
  group('InterestedIn.requiredFor', () {
    test('citas y ambas sin nada elegido lo exigen', () {
      expect(InterestedIn.requiredFor(IntentMode.dating, const <String>[]),
          isTrue);
      expect(
          InterestedIn.requiredFor(IntentMode.both, const <String>[]), isTrue);
    });

    test('amistad y grupos no: ahí el género no filtra', () {
      expect(InterestedIn.requiredFor(IntentMode.friends, const <String>[]),
          isFalse);
      expect(InterestedIn.requiredFor(IntentMode.groups, const <String>[]),
          isFalse);
    });

    test('con algo elegido ya no hace falta', () {
      expect(InterestedIn.requiredFor(IntentMode.dating, <String>['female']),
          isFalse);
    });

    test('valores en blanco cuentan como vacío', () {
      expect(InterestedIn.requiredFor(IntentMode.dating, <String>[' ', '']),
          isTrue);
    });
  });

  group('InterestedIn.trait', () {
    test('escribe en preferences.interestedIn (lo que leen feed y discovery)',
        () {
      expect(InterestedIn.trait.group, 'preferences');
      expect(InterestedIn.trait.field, 'interestedIn');
    });

    test('ofrece las tres casillas que entiende GenderMatching', () {
      expect(InterestedIn.options.map((o) => o.value),
          GenderMatching.interestBuckets);
    });

    test('describe traduce los códigos', () {
      expect(
          InterestedIn.describe(<String>['female', 'male']), 'Mujer, Hombre');
      expect(InterestedIn.describe(const <String>[]), isEmpty);
    });
  });

  group('Cambiar de modo', () {
    test(
        'amistad → citas con la lista vacía: pregunta y guarda ANTES el '
        'interés que el modo', () async {
      final _Calls calls = _Calls();
      final IntentSwitchOutcome outcome = await _switch(
        calls,
        from: IntentMode.friends,
        to: IntentMode.dating,
        answer: <String>['female'],
      );

      expect(outcome, IntentSwitchOutcome.saved);
      expect(calls.log, <String>['ask', 'saveInterest', 'saveMode']);
      expect(calls.savedInterest, <String>['female']);
      expect(calls.savedMode, IntentMode.dating);
    });

    test('grupos → ambas también pregunta', () async {
      final _Calls calls = _Calls();
      await _switch(calls,
          from: IntentMode.groups,
          to: IntentMode.both,
          answer: <String>['male', 'non_binary']);

      expect(calls.savedInterest, <String>['male', 'non_binary']);
      expect(calls.savedMode, IntentMode.both);
    });

    test('si cierra sin elegir, NO se cambia de modo', () async {
      final _Calls calls = _Calls();
      final IntentSwitchOutcome outcome = await _switch(calls,
          from: IntentMode.friends, to: IntentMode.dating, answer: null);

      expect(outcome, IntentSwitchOutcome.cancelled);
      expect(calls.log, <String>['ask']);
      expect(calls.savedMode, isNull);
    });

    test('una respuesta vacía cuenta como cancelar', () async {
      final _Calls calls = _Calls();
      final IntentSwitchOutcome outcome = await _switch(calls,
          from: IntentMode.friends,
          to: IntentMode.dating,
          answer: const <String>[]);

      expect(outcome, IntentSwitchOutcome.cancelled);
      expect(calls.savedMode, isNull);
    });

    test('si falla guardar el interés, tampoco se guarda el modo', () async {
      final List<String> log = <String>[];
      await expectLater(
        switchIntentModeWithInterest(
          current: IntentMode.friends,
          chosen: IntentMode.dating,
          interestedIn: const <String>[],
          askInterestedIn: () async => <String>['female'],
          saveInterestedIn: (_) async => throw StateError('sin red'),
          saveMode: (_) async => log.add('saveMode'),
        ),
        throwsStateError,
      );
      expect(log, isEmpty);
    });

    test('con el interés ya elegido no pregunta', () async {
      final _Calls calls = _Calls();
      await _switch(calls,
          from: IntentMode.friends,
          to: IntentMode.dating,
          interestedIn: <String>['male']);

      expect(calls.log, <String>['saveMode']);
    });

    test('hacia amistad o grupos no pregunta aunque esté vacío', () async {
      final _Calls calls = _Calls();
      await _switch(calls, from: IntentMode.dating, to: IntentMode.friends);
      await _switch(calls, from: IntentMode.friends, to: IntentMode.groups);

      expect(calls.log, <String>['saveMode', 'saveMode']);
    });

    test(
        'quien YA estaba en citas con la lista vacía: al confirmar su modo se '
        'le pide y se guarda sin reescribir el modo', () async {
      final _Calls calls = _Calls();
      final IntentSwitchOutcome outcome = await _switch(calls,
          from: IntentMode.dating,
          to: IntentMode.dating,
          answer: <String>['female']);

      expect(outcome, IntentSwitchOutcome.saved);
      expect(calls.log, <String>['ask', 'saveInterest']);
    });

    test('mismo modo y nada que pedir: no toca nada', () async {
      final _Calls calls = _Calls();
      final IntentSwitchOutcome outcome = await _switch(calls,
          from: IntentMode.dating,
          to: IntentMode.dating,
          interestedIn: <String>['female']);

      expect(outcome, IntentSwitchOutcome.unchanged);
      expect(calls.log, isEmpty);
    });
  });

  group('InterestedIn.promptBeforeFeed (quien ya estaba en citas)', () {
    test('citas o ambas con la lista vacía: se pide antes del feed', () {
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.dating, current: const <String>[]),
          isTrue);
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.both, current: const <String>['']),
          isTrue);
    });

    test('con algo elegido, en amistad/grupos o siendo bot: no', () {
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.dating, current: <String>['male']),
          isFalse);
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.friends, current: const <String>[]),
          isFalse);
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.groups, current: const <String>[]),
          isFalse);
      expect(
          InterestedIn.promptBeforeFeed(
              mode: IntentMode.dating, current: const <String>[], isBot: true),
          isFalse);
    });
  });

  test(
      'el caso del informe: Carlos pasa de amistad a citas, se le pide "Me '
      'interesan" y, con "Mujer", deja de salir a quien busca hombres',
      () async {
    final _Calls calls = _Calls();
    await _switch(calls,
        from: IntentMode.friends,
        to: IntentMode.dating,
        answer: <String>['female']);

    // Desde el lado de un hombre que busca hombres, FeedFilter mira si Carlos
    // le quiere a él: wants(interestedIn de Carlos, 'male'). Antes del arreglo
    // se cambiaba de modo sin preguntar, la lista seguía vacía y salía siempre.
    final List<String> carlos = calls.savedInterest ?? const <String>[];
    expect(calls.savedMode, IntentMode.dating);
    expect(GenderMatching.wants(carlos, 'male'), isFalse);
    expect(GenderMatching.wants(carlos, 'female'), isTrue);
  });
}
