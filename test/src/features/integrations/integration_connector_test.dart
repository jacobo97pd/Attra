import 'package:attra/src/features/integrations/domain/integration_connector.dart';
import 'package:attra/src/features/integrations/integrations_config.dart';
import 'package:attra/src/features/settings/domain/setting_definition.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnector implements IntegrationConnector {
  _FakeConnector(this.key);
  final String key;
  bool connected = false;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  bool handles(String settingKey) => settingKey == key;

  @override
  Future<bool> connect(SettingDefinition def) async {
    connectCalls++;
    connected = true;
    return true;
  }

  @override
  Future<void> disconnect(SettingDefinition def) async {
    disconnectCalls++;
    connected = false;
  }
}

SettingDefinition _def(String key) => SettingDefinition(
      key: key,
      sectionKey: 'integrations',
      type: SettingType.boolean,
      label: key,
      description: '',
      defaultValue: false,
    );

void main() {
  group('CompositeIntegrationConnector', () {
    test('enruta al conector que declara la clave', () async {
      final _FakeConnector spotify = _FakeConnector('integrations.spotify');
      final _FakeConnector instagram = _FakeConnector('integrations.instagram');
      final CompositeIntegrationConnector composite =
          CompositeIntegrationConnector(<IntegrationConnector>[spotify, instagram]);

      expect(composite.handles('integrations.spotify'), isTrue);
      expect(composite.handles('integrations.instagram'), isTrue);
      expect(composite.handles('integrations.contactSync'), isFalse);

      await composite.connect(_def('integrations.spotify'));
      expect(spotify.connectCalls, 1);
      expect(instagram.connectCalls, 0);

      await composite.disconnect(_def('integrations.instagram'));
      expect(instagram.disconnectCalls, 1);
      expect(spotify.disconnectCalls, 0);
    });

    test('clave no gestionada => connect devuelve false (no-op)', () async {
      const CompositeIntegrationConnector composite =
          CompositeIntegrationConnector(<IntegrationConnector>[]);
      expect(composite.handles('integrations.spotify'), isFalse);
      expect(await composite.connect(_def('integrations.spotify')), isFalse);
    });
  });

  test('IntegrationsConfig sin configurar usa placeholder', () {
    // Por defecto (sin --dart-define) el Client ID es el placeholder.
    expect(IntegrationsConfig.isSpotifyConfigured, isFalse);
    expect(IntegrationsConfig.spotifyScopes, 'user-top-read');
  });
}
