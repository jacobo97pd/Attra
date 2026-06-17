import '../../settings/domain/setting_definition.dart';

/// Error legible de una operacion de integracion (cancelacion, OAuth, backend…).
class IntegrationException implements Exception {
  const IntegrationException(this.message);
  final String message;
  @override
  String toString() => 'IntegrationException: $message';
}

/// Contrato para conectar/desconectar integraciones externas (Spotify,
/// Instagram, contactos…) desde el toggle generico de Ajustes. El
/// SettingsController delega en esto cuando `handles(def.key)` es true; si no,
/// el toggle se comporta como un booleano normal (solo consentimiento).
abstract class IntegrationConnector {
  /// True si esta integracion gestiona esta clave de ajuste.
  bool handles(String settingKey);

  /// Lanza el flujo de conexion (OAuth, permiso…). Devuelve true si quedo
  /// conectado. No persiste el flag: lo hace el SettingsController al volver.
  Future<bool> connect(SettingDefinition def);

  /// Revoca/desconecta la integracion.
  Future<void> disconnect(SettingDefinition def);
}

/// Agrupa varios conectores (uno por servicio) tras una sola interfaz.
class CompositeIntegrationConnector implements IntegrationConnector {
  const CompositeIntegrationConnector(this._connectors);

  final List<IntegrationConnector> _connectors;

  IntegrationConnector? _forKey(String key) {
    for (final IntegrationConnector c in _connectors) {
      if (c.handles(key)) return c;
    }
    return null;
  }

  @override
  bool handles(String settingKey) => _forKey(settingKey) != null;

  @override
  Future<bool> connect(SettingDefinition def) async =>
      await _forKey(def.key)?.connect(def) ?? false;

  @override
  Future<void> disconnect(SettingDefinition def) async =>
      _forKey(def.key)?.disconnect(def);
}
