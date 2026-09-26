import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/premium_feature.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:attra/src/features/monetization/presentation/entitlement_controller.dart';
import 'package:attra/src/features/settings/data/settings_repository.dart';
import 'package:attra/src/features/settings/domain/setting_definition.dart';
import 'package:attra/src/features/settings/domain/settings_catalog.dart';
import 'package:attra/src/features/settings/presentation/settings_controller.dart';
import 'package:attra/src/features/settings/presentation/settings_section_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio en memoria: lo que importa aquí es QUÉ se persiste.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository([Map<String, dynamic>? initial])
      : stored = <String, dynamic>{...?initial};

  final Map<String, dynamic> stored;
  final List<Map<String, Object?>> patches = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> loadSettings(String uid) async =>
      <String, dynamic>{...stored};

  @override
  Future<void> patchValues(String uid, Map<String, Object?> values) async {
    patches.add(values);
    stored.addAll(values);
  }

  @override
  Future<void> recordAudit({
    required String uid,
    required String event,
    required String settingKey,
    Object? previousValue,
    Object? newValue,
    String reasonCode = 'user_self_service',
  }) async {}

  @override
  Future<void> recordConsent({
    required String uid,
    required SettingDefinition definition,
    required bool granted,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa aquí');
}

class _FakeEntitlementService implements EntitlementService {
  _FakeEntitlementService(this.value);
  final UserEntitlements value;
  @override
  Future<UserEntitlements> getEntitlements(String uid) async => value;
  @override
  Stream<UserEntitlements> watchEntitlements(String uid) =>
      Stream<UserEntitlements>.value(value);
}

class _FakeFlagService implements FeatureFlagService {
  @override
  Future<MonetizationFeatureFlags> fetchFlags() async =>
      const MonetizationFeatureFlags();
  @override
  Stream<MonetizationFeatureFlags> watchFlags() =>
      Stream<MonetizationFeatureFlags>.value(const MonetizationFeatureFlags());
}

/// Controlador de ajustes cableado EXACTAMENTE como en HomeShell: el gate lo
/// decide `EntitlementController.unlocksSetting`.
Future<(SettingsController, _FakeSettingsRepository)> _settingsFor(
  SubscriptionTier tier, {
  Map<String, dynamic>? stored,
}) async {
  final EntitlementController entitlements = EntitlementController(
    entitlementService:
        _FakeEntitlementService(UserEntitlements.forTier(uid: 'u', tier: tier)),
    featureFlagService: _FakeFlagService(),
    uid: 'u',
  );
  await entitlements.load();
  final _FakeSettingsRepository repo = _FakeSettingsRepository(stored);
  final SettingsController settings = SettingsController(
    repository: repo,
    uid: 'u',
    onDeleteAccount: () async {},
    featureResolver: entitlements.unlocksSetting,
  );
  await settings.load();
  return (settings, repo);
}

SettingDefinition _def(String key) => SettingsCatalog.definitionByKey(key)!;

void main() {
  test('el incógnito se desbloquea con SU función (de Plus)', () {
    expect(SettingsCatalog.requiredFeatureFor(_def('privacy.incognito')),
        PremiumFeature.incognitoMode);
  });

  test('Plus puede activar el incógnito (antes: "Disponible con Premium")',
      () async {
    final (SettingsController c, _FakeSettingsRepository repo) =
        await _settingsFor(SubscriptionTier.plus);
    final SettingDefinition incognito = _def('privacy.incognito');
    final EffectiveSetting eff = c.effectiveFor(incognito);
    expect(eff.locked, isFalse);
    await c.setValue(incognito, true);
    expect(repo.stored['privacy.incognito'], isTrue);
    // El resto de ajustes de pago (sin función propia) piden cualquier plan.
    expect(c.effectiveFor(_def('security.discreetIcon')).locked, isFalse);
  });

  test('Free lo ve bloqueado con el plan que de verdad se vende', () async {
    final (SettingsController c, _FakeSettingsRepository repo) =
        await _settingsFor(SubscriptionTier.free);
    final SettingDefinition incognito = _def('privacy.incognito');
    final EffectiveSetting eff = c.effectiveFor(incognito);
    expect(eff.locked, isTrue);
    expect(eff.lockedReason, 'Disponible con Plus');
    expect(c.requiredPlanLabel(incognito), 'Plus');
    await c.setValue(incognito, true);
    expect(repo.patches, isEmpty, reason: 'sin plan no se enciende');
  });

  test('quien dejó el incógnito encendido y ya no paga PUEDE apagarlo',
      () async {
    final (SettingsController c, _FakeSettingsRepository repo) =
        await _settingsFor(
      SubscriptionTier.free,
      stored: <String, dynamic>{'privacy.incognito': true},
    );
    final SettingDefinition incognito = _def('privacy.incognito');
    final EffectiveSetting eff = c.effectiveFor(incognito);
    expect(eff.locked, isFalse, reason: 'antes se quedaba bloqueado en ON');
    // Y dice que ya NO se aplica: el backend vuelve a listarle con su ciudad
    // y su actividad. Antes el interruptor seguía en ON sin ninguna pista.
    expect(eff.paused, isTrue);
    expect(eff.notice, contains('pausa'));
    expect(eff.notice, contains('ciudad'));
    expect(eff.notice, contains('Plus'));
    await c.setValue(incognito, false);
    expect(repo.stored['privacy.incognito'], isFalse);
    // Y una vez apagado, sin plan no se vuelve a encender.
    expect(c.effectiveFor(incognito).locked, isTrue);
    expect(c.effectiveFor(incognito).notice, isNull,
        reason: 'apagado ya no hay nada en pausa: solo el bloqueo');
    expect(c.effectiveFor(incognito).lockedReason, 'Disponible con Plus');
    await c.setValue(incognito, true);
    expect(repo.stored['privacy.incognito'], isFalse);
  });

  test('con plan, el incógnito encendido no está en pausa', () async {
    final (SettingsController c, _) = await _settingsFor(
      SubscriptionTier.plus,
      stored: <String, dynamic>{'privacy.incognito': true},
    );
    final EffectiveSetting eff = c.effectiveFor(_def('privacy.incognito'));
    expect(eff.locked, isFalse);
    expect(eff.notice, isNull);
    expect(eff.paused, isFalse);
  });

  testWidgets('Privacidad enseña el aviso de pausa bajo el interruptor en ON',
      (WidgetTester tester) async {
    late SettingsController c;
    await tester.runAsync(() async {
      (c, _) = await _settingsFor(
        SubscriptionTier.free,
        stored: <String, dynamic>{'privacy.incognito': true},
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: SettingsSectionScreen(
        controller: c,
        sectionKey: SettingsCatalog.secPrivacy,
      ),
    ));
    await tester.pump();

    expect(find.textContaining('En pausa'), findsOneWidget);
    final SwitchListTile tile = tester.widget<SwitchListTile>(find.ancestor(
      of: find.text('Modo incognito'),
      matching: find.byType(SwitchListTile),
    ));
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull, reason: 'se tiene que poder apagar');
  });

  test('sin resolver de entitlements todo lo de pago queda bloqueado',
      () async {
    final SettingsController c = SettingsController(
      repository: _FakeSettingsRepository(),
      uid: 'u',
      onDeleteAccount: () async {},
    );
    await c.load();
    expect(c.effectiveFor(_def('privacy.incognito')).locked, isTrue);
    // Lo gratuito no se ve afectado.
    expect(c.effectiveFor(_def('privacy.hideProfile')).locked, isFalse);
  });
}
