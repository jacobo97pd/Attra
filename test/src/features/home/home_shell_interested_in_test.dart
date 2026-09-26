import 'dart:async';
import 'dart:typed_data';

import 'package:attra/l10n/app_localizations.dart';
import 'package:attra/src/features/ai_visual/data/ai_visual_service.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/data/reply_suggestion_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/feed/data/ranking_signals_repository.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/home/presentation/home_shell.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/like.dart';
import 'package:attra/src/features/match/domain/user_match.dart';
import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:attra/src/features/onboarding/domain/interested_in.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_prompt.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:attra/src/features/profile/domain/profile_trait.dart';
import 'package:attra/src/features/settings/data/settings_repository.dart';
import 'package:attra/src/features/social/domain/intent_mode.dart';
import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C11, lo que faltaba: quien YA estaba en citas con "Me interesan" vacío
/// (se registró en amistad o grupos y cambió de modo antes del arreglo) nunca
/// volvía a ver la pregunta y seguía viendo, y saliéndole a, todos los géneros.
/// Ahora Descubrir se la pide en lugar de cargar el feed, sin bloquear el resto
/// de pestañas. Y el selector "Qué buscas" del HomeShell (antes solo probado en
/// su helper puro) pide el interés antes de guardar un modo de citas.
AppUser _user({
  IntentMode mode = IntentMode.dating,
  List<String> interestedIn = const <String>[],
  bool isBot = false,
}) =>
    AppUser(
      uid: 'me',
      email: 'me@attra.test',
      displayName: 'Carlos',
      photoUrl: '',
      onboardingCompleted: true,
      profileCompleted: true,
      profileCompletionPercent: 80,
      isBot: isBot,
      gender: 'male',
      intentMode: mode,
      interestedIn: interestedIn,
    );

class _Calls {
  final List<String> log = <String>[];
  final List<(ProfileTraitDefinition, Object?)> traits =
      <(ProfileTraitDefinition, Object?)>[];
  final List<IntentMode> modes = <IntentMode>[];
  Object? traitError;
  Object? modeError;
}

Finder get _gate => find.byKey(const ValueKey<String>('interested-in-gate'));

Finder get _gateSave =>
    find.byKey(const ValueKey<String>('interested-in-gate-save'));

Finder _pill(String value) =>
    find.byKey(ValueKey<String>('interested-in-$value'));

/// Deja correr animaciones (hojas, snackbars) sin pumpAndSettle: el perfil
/// se queda cargando con un indicador infinito.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Con el feed montado, su refresco de ubicación arma un timeout de unos
/// segundos (en test no hay GPS): se deja vencer para cerrar limpio.
Future<void> _drainFeed(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  expect(tester.takeException(), isNull);
}

/// [reloadOnSave] imita a SessionController.setProfileTrait, que tras escribir
/// recarga el usuario: el HomeShell recibe el AppUser nuevo.
Future<_Calls> _pumpShell(
  WidgetTester tester,
  AppUser user, {
  bool reloadOnSave = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final _Calls calls = _Calls();
  final ValueNotifier<AppUser> current = ValueNotifier<AppUser>(user);
  addTearDown(current.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ValueListenableBuilder<AppUser>(
      valueListenable: current,
      builder: (BuildContext context, AppUser user, Widget? _) => HomeShell(
        user: user,
        onLogout: () {},
        onLoadProfileState: () => Completer<ProfileCompletionState>().future,
        onUploadAdditionalPhoto: ({
          required Uint8List photoBytes,
          required String fileExtension,
          required String source,
        }) async {},
        onDeleteAdditionalPhoto: (String _) async {},
        onAddPrompt: (String _) async {},
        onClaimReward: (String _) async {},
        onLoadSeedProfiles: () async => const <SeedProfile>[],
        onDeleteAccount: () async {},
        onLoadProfileRaw: () => Completer<Map<String, dynamic>>().future,
        onSetTrait: (ProfileTraitDefinition def, Object? value) async {
          calls.log.add('trait');
          calls.traits.add((def, value));
          final Object? error = calls.traitError;
          if (error != null) throw error;
          if (reloadOnSave) {
            current.value = _user(
              mode: user.intentMode,
              interestedIn: List<String>.from(value! as List<Object?>),
            );
          }
        },
        onSetTraitVisibility: (
          String traitKey, {
          required bool visibleInProfile,
          required bool useForMatching,
          required bool useForFilters,
        }) async {},
        onLoadProfilePrompts: () async => const <ProfilePrompt>[],
        onSaveProfilePrompts: (List<ProfilePrompt> _) async {},
        onLoadIntroMedia: () async => (audio: null, video: null),
        onUploadIntroAudio: ({
          required Uint8List bytes,
          required String contentType,
          required String extension,
          required int durationMs,
        }) async {},
        onDeleteIntroAudio: () async {},
        onUploadIntroVideo: ({
          required Uint8List bytes,
          required String contentType,
          required String extension,
          required int durationMs,
        }) async {},
        onDeleteIntroVideo: () async {},
        settingsRepository: _Settings(),
        entitlementService: _Entitlements(),
        featureFlagService: _Flags(),
        matchService: _MatchService(),
        chatService: _ChatService(),
        onSetIntentMode: (IntentMode mode) async {
          calls.log.add('mode');
          calls.modes.add(mode);
          final Object? error = calls.modeError;
          if (error != null) throw error;
        },
        profileSummaryRepository: _Summaries(),
        rankingSignalsRepository: _Ranking(),
        storyService: _StoryService(),
        aiVisualService: _AiVisual(),
        onSetAiConsent: (bool _) async {},
        replySuggestionService: _Replies(),
        onSetChatSuggestionsConsent: (bool _) async {},
        onSetSlowDating: (bool _) async {},
        onSetThemeMode: (ThemeMode _) async {},
        onRepublishDiscovery: () async {},
        onSetTravelLocation: ({
          required bool active,
          String iso2 = '',
          String city = '',
          String country = '',
        }) async {},
        onLoadProfileByUid: (String _) async => null,
      ),
    ),
  ));
  await _settle(tester);
  return calls;
}

void main() {
  testWidgets(
      'en citas sin "Me interesan", Descubrir lo pide en vez de cargar el '
      'feed, y las demás pestañas siguen a mano', (WidgetTester tester) async {
    await _pumpShell(tester, _user());

    expect(_gate, findsOneWidget);
    expect(find.byType(FeedScreen), findsNothing);
    expect(tester.widget<FilledButton>(_gateSave).onPressed, isNull,
        reason: 'guardar la lista vacía es justo el fallo');

    // No es un modal: la barra de navegación responde.
    await tester.tap(find.byType(NavigationDestination).at(2));
    await _settle(tester);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'elegir y guardar escribe preferences.interestedIn por la vía de '
      'siempre (onSetTrait), sin tocar el modo', (WidgetTester tester) async {
    final _Calls calls = await _pumpShell(tester, _user());

    await tester.tap(_pill('female'));
    await tester.pump();
    await tester.tap(_gateSave);
    await _settle(tester);

    expect(calls.log, <String>['trait']);
    expect(calls.traits.single.$1.group, InterestedIn.trait.group);
    expect(calls.traits.single.$1.field, InterestedIn.trait.field);
    expect(calls.traits.single.$2, <String>['female']);
  });

  testWidgets(
      'con el usuario recargado (ya con "Me interesan") vuelve el feed, sin '
      'volver a preguntar', (WidgetTester tester) async {
    await _pumpShell(tester, _user(), reloadOnSave: true);

    await tester.tap(_pill('female'));
    await tester.pump();
    await tester.tap(_gateSave);
    await _settle(tester);

    expect(_gate, findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    // El feed se monta con la preferencia nueva, no con la lista vacía.
    expect(
        tester.widget<FeedScreen>(find.byType(FeedScreen)).user?.interestedIn,
        <String>['female']);
    await _drainFeed(tester);
  });

  testWidgets('quien ya eligió no ve el paso', (WidgetTester tester) async {
    await _pumpShell(tester, _user(interestedIn: <String>['male']));
    expect(_gate, findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    await _drainFeed(tester);
  });

  testWidgets('en amistad tampoco: ahí el género no filtra',
      (WidgetTester tester) async {
    await _pumpShell(tester, _user(mode: IntentMode.friends));
    expect(_gate, findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    await _drainFeed(tester);
  });

  testWidgets('si guardar falla, avisa y el paso sigue ahí para reintentar',
      (WidgetTester tester) async {
    final _Calls calls = await _pumpShell(tester, _user());
    calls.traitError = StateError('sin red');

    await tester.tap(_pill('male'));
    await tester.pump();
    await tester.tap(_gateSave);
    await _settle(tester);

    expect(
        find.text('No se pudo guardar. Inténtalo de nuevo.'), findsOneWidget);
    expect(_gate, findsOneWidget);
    expect(tester.widget<FilledButton>(_gateSave).onPressed, isNotNull);
  });

  testWidgets(
      '"Qué buscas" desde el HomeShell: pasar a Ambas pide "Me interesan" y lo '
      'guarda ANTES que el modo', (WidgetTester tester) async {
    final _Calls calls = await _pumpShell(tester, _user());

    await tester.tap(
        find.byKey(const ValueKey<String>('interested-in-gate-change-mode')));
    await _settle(tester);
    await tester.tap(find.text('Ambas'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);

    // La hoja de "Me interesan" (la misma del perfil), encima de todo.
    final Finder sheetSave =
        find.byKey(const ValueKey<String>('interested-in-save'));
    expect(sheetSave, findsOneWidget);
    await tester.tap(
        find.descendant(of: find.byType(BottomSheet), matching: _pill('male')));
    await tester.pump();
    await tester.tap(sheetSave);
    await _settle(tester);

    expect(calls.log, <String>['trait', 'mode']);
    expect(calls.traits.single.$2, <String>['male']);
    expect(calls.modes, <IntentMode>[IntentMode.both]);
  });

  testWidgets(
      '"Qué buscas": cerrar "Me interesan" sin elegir NO cambia el modo a '
      'citas', (WidgetTester tester) async {
    final _Calls calls =
        await _pumpShell(tester, _user(mode: IntentMode.dating));

    await tester.tap(
        find.byKey(const ValueKey<String>('interested-in-gate-change-mode')));
    await _settle(tester);
    await tester.tap(find.text('Ambas'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    await tester.tapAt(const Offset(20, 20)); // fuera de la hoja
    await _settle(tester);

    expect(calls.log, isEmpty);
    expect(find.text('Elige a quién quieres conocer para pasar a citas.'),
        findsOneWidget);
  });

  testWidgets(
      '"Qué buscas": si "Me interesan" se guarda pero el modo falla, el feed se '
      'recarga igual con la preferencia nueva', (WidgetTester tester) async {
    final _Calls calls = await _pumpShell(tester, _user(), reloadOnSave: true);
    calls.modeError = StateError('sin red');

    await tester.tap(
        find.byKey(const ValueKey<String>('interested-in-gate-change-mode')));
    await _settle(tester);
    await tester.tap(find.text('Ambas'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(BottomSheet), matching: _pill('female')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('interested-in-save')));
    await _settle(tester);

    expect(calls.log, <String>['trait', 'mode']);
    expect(find.text('No se pudo cambiar el modo.'), findsOneWidget);
    final FeedScreen feed = tester.widget<FeedScreen>(find.byType(FeedScreen));
    expect(feed.user?.interestedIn, <String>['female']);
    expect(feed.reloadToken, 1, reason: 'antes no se recargaba');
    await _drainFeed(tester);
  });

  testWidgets('"Qué buscas": pasar a amistad no pide nada',
      (WidgetTester tester) async {
    final _Calls calls = await _pumpShell(tester, _user());

    await tester.tap(
        find.byKey(const ValueKey<String>('interested-in-gate-change-mode')));
    await _settle(tester);
    await tester.tap(find.text('Amistad'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await _settle(tester);

    expect(
        find.byKey(const ValueKey<String>('interested-in-save')), findsNothing);
    expect(calls.log, <String>['mode']);
    expect(calls.modes, <IntentMode>[IntentMode.friends]);
  });
}

/// Servicios que estas pruebas no deben tocar: si algo los llama, lo dice.
mixin _Unexpected {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}

class _Settings with _Unexpected implements SettingsRepository {}

/// La carga de plan y flags se queda pendiente (sin red): el HomeShell sigue
/// en free con los valores por defecto, que es lo que estas pruebas necesitan.
class _Entitlements with _Unexpected implements EntitlementService {
  @override
  Future<UserEntitlements> getEntitlements(String uid) =>
      Completer<UserEntitlements>().future;
}

class _Flags with _Unexpected implements FeatureFlagService {
  @override
  Future<MonetizationFeatureFlags> fetchFlags() =>
      Completer<MonetizationFeatureFlags>().future;
}

class _Ranking with _Unexpected implements RankingSignalsRepository {}

class _AiVisual with _Unexpected implements AiVisualService {}

class _Replies with _Unexpected implements ReplySuggestionService {}

class _MatchService implements MatchService {
  @override
  Stream<List<Like>> observeReceivedLikes(String uid) =>
      Stream<List<Like>>.value(const <Like>[]);

  @override
  Stream<List<Like>> observeSentLikes(String uid) =>
      Stream<List<Like>>.value(const <Like>[]);

  @override
  Stream<List<UserMatch>> observeMatches(String uid) =>
      Stream<List<UserMatch>>.value(const <UserMatch>[]);

  @override
  Future<Set<String>> fetchExcludedUids(String uid) async => <String>{};

  @override
  Future<Set<String>> fetchDislikedUids(String uid) async => <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}

class _ChatService implements ChatService {
  @override
  Stream<List<Chat>> observeChats(String uid) =>
      Stream<List<Chat>>.value(const <Chat>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}

class _Summaries implements ProfileSummaryRepository {
  @override
  Future<ProfileSummary> fetch(String uid) async =>
      ProfileSummary(uid: uid, displayName: 'Perfil $uid', photoUrl: '');

  @override
  ProfileSummary? peek(String uid) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}

class _StoryService implements StoryService {
  @override
  Stream<Map<String, List<Story>>> observeLiveStoriesForMatches({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) =>
      const Stream<Map<String, List<Story>>>.empty();

  @override
  Future<bool> storiesEnabled() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No se esperaba ${invocation.memberName}');
}
