import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/home/presentation/home_screen.dart';
import 'package:attra/src/features/profile/domain/profile_prompt.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/profile/domain/profile_trait.dart';
import 'package:attra/src/features/profile/presentation/profile_strength_card.dart';
import 'package:attra/src/features/profile/presentation/profile_view_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _recordChannel =
    MethodChannel('com.llfbandit.record/messages');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_recordChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_recordChannel, null);
  });

  for (final bool dark in <bool>[true, false]) {
    testWidgets('el perfil propio cabe a 200% en ${dark ? 'oscuro' : 'claro'}',
        (WidgetTester tester) async {
      _smallScreen(tester);
      final _ProfileHarness profile = _ProfileHarness();
      await tester.pumpWidget(_host(profile.screen(), dark: dark, scale: 2));
      await tester.pumpAndSettle();

      expect(find.text(_longName), findsOneWidget);
      expect(find.text('Audio y vídeo de presentación'), findsOneWidget);
      for (final String task in _tasks) {
        expect(find.text(task), findsOneWidget);
      }
      expect(find.text('Una respuesta completa, con espacio para ser yo.'),
          findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Preguntas de perfil')).dy,
        lessThan(tester.getTopLeft(find.text('Tu experiencia')).dy),
      );
      await tester.ensureVisible(find.text('Eliminar cuenta'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'el perfil público conserva notas largas a 200% en '
        '${dark ? 'oscuro' : 'claro'}', (WidgetTester tester) async {
      _smallScreen(tester);
      await tester.pumpWidget(_host(
        ProfileViewScreen(profile: _publicProfile()),
        dark: dark,
        scale: 2,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sobre mí'), findsOneWidget);
      expect(find.text('Intereses'), findsOneWidget);
      expect(find.text(_longPlace), findsOneWidget);
      expect(find.text('Mi domingo perfecto'), findsOneWidget);
      expect(find.text(_answer), findsOneWidget);
      expect(find.text('Lo que me hace reír'), findsOneWidget);
      await tester.ensureVisible(find.text('Los juegos de palabras.'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('las filas del perfil conservan cada destino y el saldo',
      (WidgetTester tester) async {
    final _ProfileHarness profile = _ProfileHarness();
    await tester.pumpWidget(_host(profile.screen()));
    await tester.pumpAndSettle();

    for (final (String label, String call) in <(String, String)>[
      ('Qué buscas', 'intent'),
      ('Grupos y planes', 'groups'),
      ('SafeDate', 'safe'),
      ('IA visual · Pro', 'ai'),
      ('Boosts y Swipes', 'boosts'),
      ('Tu plan: Pro', 'upgrade'),
      ('Ajustes', 'settings'),
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(profile.calls.last, call);
    }
    expect(find.text('Tienes 2 boosts y 7 swipes.'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(profile.calls, <String>[
      'intent',
      'groups',
      'safe',
      'ai',
      'boosts',
      'upgrade',
      'settings'
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('mantiene límite de cinco fotos y permite borrar con su callback',
      (WidgetTester tester) async {
    final _ProfileHarness profile = _ProfileHarness(photoCount: 5);
    await tester.pumpWidget(_host(profile.screen()));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subir de galería'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Tomar foto'))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.byTooltip('Eliminar foto 1'));
    await tester.pumpAndSettle();
    final Size target = tester.getSize(find.byTooltip('Eliminar foto 1'));
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Eliminar foto 1'));
    await tester.pumpAndSettle();

    expect(profile.deleted, <String>['photo-0']);
    expect(find.text('Restantes: 1'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Subir de galería'))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('completitud muestra todas las tareas y conserva editar',
      (WidgetTester tester) async {
    _smallScreen(tester);
    int edits = 0;
    await tester.pumpWidget(_host(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ProfileStrengthCard(
              percent: 75,
              pendingTasks: _tasks,
              onEdit: () => edits += 1,
            ),
          ),
        ),
        scale: 2));
    await tester.pumpAndSettle();
    for (final String task in _tasks) {
      expect(find.text(task), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Completar perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completar perfil'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    final LinearProgressIndicator progress =
        tester.widget(find.byType(LinearProgressIndicator));
    expect(progress.semanticsLabel, 'Completitud del perfil');
    expect(progress.semanticsValue, '75');
    expect(tester.takeException(), isNull);
  });
}

const String _longName = 'Alejandra María de los Ángeles';
const String _longPlace =
    'San Sebastián de los Reyes, Comunidad de Madrid, España';
const String _answer = 'Un café largo, una exposición y terminar leyendo '
    'en un parque sin mirar el reloj. Me gusta descubrir lugares nuevos '
    'y compartirlos con alguien que disfrute de una conversación tranquila.';
const List<String> _tasks = <String>[
  'Añadir una foto',
  'Escribir una respuesta',
  'Completar idiomas',
  'Añadir una presentación',
  'Revisar información personal',
  'Completar preferencias',
];

void _smallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child, {bool dark = true, double scale = 1}) => MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: child,
    );

class _ProfileHarness {
  _ProfileHarness({int photoCount = 1})
      : photos = List<AdditionalPhoto>.generate(
          photoCount,
          (int i) => AdditionalPhoto(
              url: '', storagePath: 'photo-$i', source: 'gallery', order: i),
        );

  final List<AdditionalPhoto> photos;
  final List<String> calls = <String>[];
  final List<String> deleted = <String>[];

  Widget screen() => HomeScreen(
        user: const AppUser(
          uid: 'me',
          email: 'alejandra.maria.delosangeles@attra.example',
          displayName: _longName,
          photoUrl: '',
          onboardingCompleted: true,
          profileCompleted: true,
          profileCompletionPercent: 75,
          isBot: false,
          boostBalance: 2,
          swipeBalance: 7,
        ),
        onLogout: () => calls.add('logout'),
        onLoadProfileState: () async => ProfileCompletionState(
          percent: 75,
          pendingTasks: _tasks,
          availableRewards: const <String>[],
          claimedRewards: const <String>[],
          additionalPhotos: List<AdditionalPhoto>.of(photos),
          prompts: const <String>[
            'Una respuesta completa, con espacio para ser yo.',
          ],
          locationPermissionStatus: 'denied',
          locationGranted: false,
        ),
        onUploadAdditionalPhoto: ({
          required Uint8List photoBytes,
          required String fileExtension,
          required String source,
        }) async {},
        onDeleteAdditionalPhoto: (String path) async {
          deleted.add(path);
          photos.removeWhere(
              (AdditionalPhoto photo) => photo.storagePath == path);
        },
        onReorderPhotos: (_) async {},
        onAddPrompt: (_) async {},
        onClaimReward: (_) async {},
        onLoadSeedProfiles: () async => <SeedProfile>[],
        onDeleteAccount: () async {},
        onLoadProfileRaw: () async => <String, dynamic>{},
        onSetTrait: (ProfileTraitDefinition _, Object? value) async {},
        onSetTraitVisibility: (String _,
            {required bool visibleInProfile,
            required bool useForMatching,
            required bool useForFilters}) async {},
        onLoadProfilePrompts: () async => <ProfilePrompt>[],
        onSaveProfilePrompts: (_) async {},
        onLoadIntroMedia: () async => (audio: null, video: null),
        onUploadIntroAudio: _uploadIntro,
        onDeleteIntroAudio: () async {},
        onUploadIntroVideo: _uploadIntro,
        onDeleteIntroVideo: () async {},
        onOpenSettings: () => calls.add('settings'),
        onOpenUpgrade: () => calls.add('upgrade'),
        onOpenAiVisual: () => calls.add('ai'),
        onOpenFriendMode: () => calls.add('intent'),
        onOpenGroups: () => calls.add('groups'),
        onOpenSafeDate: () => calls.add('safe'),
        onOpenBoostStore: () => calls.add('boosts'),
        onSetSlowDating: (_) async {},
        currentPlanLabel: 'Pro',
        isProUser: true,
      );
}

Future<void> _uploadIntro({
  required Uint8List bytes,
  required String contentType,
  required String extension,
  required int durationMs,
}) async {}

SeedProfile _publicProfile() => const SeedProfile(
      id: 'person',
      displayName: _longName,
      city: 'San Sebastián de los Reyes',
      country: 'Comunidad de Madrid, España',
      bio: 'Me gustan las conversaciones largas y descubrir sitios nuevos.',
      gender: 'female',
      interestedIn: <String>['male'],
      orientation: <String>[],
      age: 31,
      jobTitle: 'Diseñadora de experiencias y servicios',
      company: 'Un estudio con un nombre muy largo',
      interests: <String>['Fotografía', 'Conversaciones largas', 'Senderismo'],
      photoUrl: '',
      isBot: false,
      botProfileVersion: 1,
      botScenario: '',
      seedQualityScore: 0,
      photos: <AdditionalPhoto>[],
      profilePrompts: <PublicPrompt>[
        PublicPrompt(
            id: 'p1', question: 'Mi domingo perfecto', answer: _answer),
        PublicPrompt(
            id: 'p2',
            question: 'Lo que me hace reír',
            answer: 'Los juegos de palabras.'),
      ],
    );
