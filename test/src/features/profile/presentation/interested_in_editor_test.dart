import 'package:attra/src/features/onboarding/domain/interested_in.dart';
import 'package:attra/src/features/profile/domain/profile_trait.dart';
import 'package:attra/src/features/profile/presentation/edit_traits_screen.dart';
import 'package:attra/src/features/profile/presentation/interested_in_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C11: no había ningún sitio donde cambiar `preferences.interestedIn` después
/// del onboarding. Quien lo dejó vacío (registro en amistad/grupos) emparejaba
/// con todos los géneros en los dos sentidos, y quien eligió una sola casilla
/// no podía ampliarla ("Mostrarme" solo estrecha).
Finder _pill(String value) =>
    find.byKey(ValueKey<String>('interested-in-$value'));

Finder get _save => find.byKey(const ValueKey<String>('interested-in-save'));

/// Abre la hoja y devuelve, al cerrarse, lo que devolvió `show` (vía [onResult]).
Future<void> _openSheet(
  WidgetTester tester, {
  List<String> initial = const <String>[],
  ValueChanged<List<String>?>? onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final List<String>? result =
                  await InterestedInSheet.show(context, initial: initial);
              onResult?.call(result);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('Hoja "Me interesan"', () {
    testWidgets('"Guardar" no se puede pulsar sin elegir nada',
        (WidgetTester tester) async {
      await _openSheet(tester);

      expect(tester.widget<FilledButton>(_save).onPressed, isNull);

      await tester.tap(_pill('male'));
      await tester.pump();
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    });

    testWidgets('devuelve lo elegido', (WidgetTester tester) async {
      List<String>? picked;
      await _openSheet(tester, onResult: (List<String>? v) => picked = v);

      await tester.tap(_pill('female'));
      await tester.pump();
      await tester.tap(_pill('non_binary'));
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(picked, <String>['female', 'non_binary']);
    });

    testWidgets('parte de lo que ya había y deja ampliarlo',
        (WidgetTester tester) async {
      List<String>? picked;
      await _openSheet(tester,
          initial: <String>['female'],
          onResult: (List<String>? v) => picked = v);

      await tester.tap(_pill('male'));
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(picked, <String>['female', 'male']);
    });
  });

  group('Editor del perfil', () {
    Future<List<(ProfileTraitDefinition, Object?)>> pumpEditor(
      WidgetTester tester,
      Map<String, dynamic> data,
    ) async {
      final List<(ProfileTraitDefinition, Object?)> writes =
          <(ProfileTraitDefinition, Object?)>[];
      await tester.pumpWidget(MaterialApp(
        home: EditTraitsScreen(
          loadData: () async => data,
          onSetTrait: (ProfileTraitDefinition def, Object? value) async {
            writes.add((def, value));
            // Simula la recarga: lo siguiente que lea la pantalla ya lo trae.
            (data['preferences'] as Map<String, dynamic>)[def.field] = value;
          },
          onSetVisibility: (
            String traitKey, {
            required bool visibleInProfile,
            required bool useForMatching,
            required bool useForFilters,
          }) async {},
        ),
      ));
      await tester.pumpAndSettle();
      return writes;
    }

    testWidgets(
        'en citas con la lista vacía avisa, y guardar escribe '
        'preferences.interestedIn', (WidgetTester tester) async {
      final Map<String, dynamic> data = <String, dynamic>{
        'profile': <String, dynamic>{'intentMode': 'dating'},
        'preferences': <String, dynamic>{'interestedIn': <String>[]},
      };
      final List<(ProfileTraitDefinition, Object?)> writes =
          await pumpEditor(tester, data);

      expect(find.textContaining('todos los géneros'), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey<String>('edit-interested-in')));
      await tester.pumpAndSettle();
      await tester.tap(_pill('male'));
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(writes, hasLength(1));
      expect(writes.single.$1.group, InterestedIn.trait.group);
      expect(writes.single.$1.field, InterestedIn.trait.field);
      expect(writes.single.$2, <String>['male']);
      // Tras recargar enseña lo guardado y el aviso desaparece.
      expect(find.text('Hombre'), findsOneWidget);
      expect(find.textContaining('todos los géneros'), findsNothing);
    });

    testWidgets('en amistad no lo trata como un problema',
        (WidgetTester tester) async {
      await pumpEditor(tester, <String, dynamic>{
        'profile': <String, dynamic>{'intentMode': 'friends'},
        'preferences': <String, dynamic>{},
      });

      expect(find.text('Me interesan'), findsOneWidget);
      expect(find.textContaining('todos los géneros'), findsNothing);
    });

    testWidgets('cerrar la hoja sin guardar no escribe nada',
        (WidgetTester tester) async {
      final List<(ProfileTraitDefinition, Object?)> writes =
          await pumpEditor(tester, <String, dynamic>{
        'profile': <String, dynamic>{'intentMode': 'dating'},
        'preferences': <String, dynamic>{
          'interestedIn': <String>['female'],
        },
      });

      expect(find.text('Mujer'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey<String>('edit-interested-in')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // fuera de la hoja
      await tester.pumpAndSettle();

      expect(writes, isEmpty);
    });
  });
}
