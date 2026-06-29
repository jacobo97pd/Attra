import 'package:flutter/foundation.dart';

import '../../../security/screen_guard.dart';
import '../../integrations/domain/integration_connector.dart';
import '../data/settings_repository.dart';
import '../domain/consent_record.dart';
import '../domain/privacy_request.dart';
import '../domain/setting_definition.dart';
import '../domain/settings_catalog.dart';

/// Valor efectivo de un ajuste: el valor actual mas si esta bloqueado y por
/// que (premium, permiso del SO...). El cliente nunca debe asumir que un toggle
/// interno implica permiso efectivo (ver "permission mismatch" del informe).
class EffectiveSetting {
  const EffectiveSetting({
    required this.definition,
    required this.value,
    required this.locked,
    this.lockedReason,
  });

  final SettingDefinition definition;
  final Object? value;
  final bool locked;
  final String? lockedReason;

  bool get boolValue => value is bool && value as bool;
  String get stringValue => value is String ? value as String : '';
}

/// Controlador de la Settings Platform para la sesion actual.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required String uid,
    required Future<void> Function() onDeleteAccount,
    bool hasPremium = false,
    bool Function()? premiumResolver,
    bool locationPermissionGranted = false,
    String region = 'EU',
    IntegrationConnector? integrationConnector,
    Future<void> Function()? onVisibilityChanged,
  })  : _repository = repository,
        _uid = uid,
        _onDeleteAccount = onDeleteAccount,
        _staticPremium = hasPremium,
        _premiumResolver = premiumResolver,
        _locationGranted = locationPermissionGranted,
        _region = region,
        _integrationConnector = integrationConnector,
        _onVisibilityChanged = onVisibilityChanged;

  /// Claves de visibilidad/ubicación que, al cambiar, requieren re-publicar el
  /// doc público de discovery para tener efecto inmediato en el feed.
  static const Set<String> _visibilityKeys = <String>{
    'privacy.hideProfile',
    'privacy.incognito',
    'privacy.showInRecommendations',
    'privacy.showDistance',
    'privacy.showActiveStatus',
    'location.showOnProfile',
    'location.precision',
  };

  /// Se invoca tras cambiar un ajuste de [_visibilityKeys] (re-publica discovery).
  final Future<void> Function()? _onVisibilityChanged;

  final SettingsRepository _repository;
  final String _uid;
  final Future<void> Function() _onDeleteAccount;
  final bool _staticPremium;

  /// Resuelve el estado Premium en vivo desde el EntitlementController. Si es
  /// null, se usa [_staticPremium]. Asi el modulo de ajustes no depende
  /// directamente del de monetizacion.
  final bool Function()? _premiumResolver;
  final bool _locationGranted;
  final String _region;

  /// Conecta integraciones externas (Spotify…) cuando el toggle las gestiona.
  final IntegrationConnector? _integrationConnector;

  /// True mientras un toggle de integracion esta en pleno flujo OAuth.
  String? _connectingKey;
  bool isConnecting(SettingDefinition def) => _connectingKey == def.key;

  bool get _hasPremium => _premiumResolver?.call() ?? _staticPremium;

  Map<String, dynamic> _raw = <String, dynamic>{};
  bool _loading = true;
  bool get isLoading => _loading;

  bool get hasPremium => _hasPremium;
  String get region => _region;

  /// @usuario de Instagram guardado (sin la @). Vacío si no hay.
  String get instagramHandle =>
      (_raw['integrations.instagramHandle'] as String?)?.trim() ?? '';

  /// Guarda (o borra) el @usuario de Instagram que se muestra en el perfil.
  /// No usa la API de Meta: solo enlaza el perfil público. Vacío = desactiva.
  Future<void> setInstagramHandle(String? handle) async {
    final String clean = (handle ?? '')
        .trim()
        .replaceAll('@', '')
        .replaceAll(RegExp(r'\s+'), '');
    final bool enabled = clean.isNotEmpty;
    _raw['integrations.instagram'] = enabled;
    _raw['integrations.instagramHandle'] = clean;
    notifyListeners();
    await _repository.patchValues(_uid, <String, Object?>{
      'integrations.instagram': enabled,
      'integrations.instagramHandle': clean,
    });
    // Se muestra en tu perfil público → re-publica discovery.
    await _onVisibilityChanged?.call();
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _raw = await _repository.loadSettings(_uid);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Calcula el valor efectivo de una definicion combinando el valor guardado,
  /// el default y las dependencias (suscripcion, permiso del SO).
  EffectiveSetting effectiveFor(SettingDefinition def) {
    final Object? value = def.coerce(_raw[def.key]);
    bool locked = false;
    String? reason;

    if (!def.editable) {
      locked = true;
      reason = 'No editable';
    } else if (def.requiresSubscription && !_hasPremium) {
      locked = true;
      reason = 'Disponible con Premium';
    } else if (def.requiresOsPermission != null &&
        !_osPermissionGranted(def.requiresOsPermission!)) {
      locked = true;
      reason = _permissionReason(def.requiresOsPermission!);
    }

    return EffectiveSetting(
      definition: def,
      value: value,
      locked: locked,
      lockedReason: reason,
    );
  }

  bool _osPermissionGranted(String permission) {
    // Solo tenemos senal real del permiso de ubicacion. Para el resto no
    // bloqueamos (se gestionan en su propio flujo de cliente).
    if (permission == 'location') {
      return _locationGranted;
    }
    return true;
  }

  String _permissionReason(String permission) {
    switch (permission) {
      case 'location':
        return 'Activa el permiso de ubicacion del dispositivo';
      case 'biometric':
        return 'Necesita biometria configurada en el dispositivo';
      case 'contacts':
        return 'Necesita permiso de contactos';
      default:
        return 'Necesita un permiso del dispositivo';
    }
  }

  /// Cambia el valor de un ajuste: persiste, audita y registra consentimiento
  /// si la definicion lo requiere. Optimista en UI.
  Future<void> setValue(SettingDefinition def, Object? newValue) async {
    final EffectiveSetting current = effectiveFor(def);
    if (current.locked) return;
    final Object? previous = current.value;
    if (previous == newValue) return;

    _raw[def.key] = newValue;
    notifyListeners();

    await _repository.patchValues(_uid, <String, Object?>{def.key: newValue});
    await _repository.recordAudit(
      uid: _uid,
      event: 'SETTING_CHANGED',
      settingKey: def.key,
      previousValue: previous,
      newValue: newValue,
    );

    if (def.consentRequired && newValue is bool) {
      // Para toggles opt-out, `true` significa RETIRAR el consentimiento.
      final bool granted = def.optOutSemantics ? !newValue : newValue;
      await _repository.recordConsent(
        uid: _uid,
        definition: def,
        granted: granted,
      );
    }

    // Si el ajuste afecta a cómo te ven los demás, re-publica discovery para que
    // surta efecto al instante (ocultarte, ciudad, precisión de ubicación…).
    if (_visibilityKeys.contains(def.key)) {
      await _onVisibilityChanged?.call();
    }

    // Efecto de dispositivo inmediato: protección anti-captura global.
    if (def.key == 'security.screenshotProtection' && newValue is bool) {
      await ScreenGuard.setGlobal(newValue);
    }
  }

  /// Error legible del ultimo intento de conexion de integracion (para la UI).
  String? lastIntegrationError;

  Future<void> toggle(SettingDefinition def, bool value) async {
    final IntegrationConnector? connector = _integrationConnector;
    // Si una integracion gestiona esta clave, el toggle dispara su flujo
    // (OAuth/permiso). El flag solo se persiste si la conexion tiene exito.
    if (connector != null && connector.handles(def.key)) {
      if (effectiveFor(def).locked) return;
      lastIntegrationError = null;
      _connectingKey = def.key;
      notifyListeners();
      try {
        if (value) {
          final bool ok = await connector.connect(def);
          if (ok) {
            await setValue(def, true);
          }
        } else {
          await connector.disconnect(def);
          await setValue(def, false);
        }
      } on IntegrationException catch (e) {
        lastIntegrationError = e.message;
      } catch (_) {
        lastIntegrationError = 'No se pudo completar la conexión.';
      } finally {
        _connectingKey = null;
        notifyListeners();
      }
      return;
    }
    return setValue(def, value);
  }

  // --- Acciones -------------------------------------------------------------

  Future<String> requestDataExport() async {
    await _repository.createPrivacyRequest(
      uid: _uid,
      type: PrivacyRequestType.export,
      detail: 'Exportacion solicitada por el usuario.',
      completeBy: DateTime.now().add(const Duration(days: 30)),
    );
    await _repository.recordAudit(
      uid: _uid,
      event: 'EXPORT_REQUEST_CREATED',
      settingKey: SettingsCatalog.actionExportData,
    );
    return 'Solicitud registrada. Te enviaremos tu archivo por email en hasta '
        '30 dias.';
  }

  /// Pausa la cuenta: oculta el perfil y deja constancia de la solicitud.
  Future<String> disableAccount() async {
    final SettingDefinition? hideProfile =
        SettingsCatalog.definitionByKey('privacy.hideProfile');
    if (hideProfile != null) {
      await setValue(hideProfile, true);
    }
    await _repository.createPrivacyRequest(
      uid: _uid,
      type: PrivacyRequestType.disable,
      detail: 'Cuenta pausada por el usuario.',
    );
    await _repository.recordAudit(
      uid: _uid,
      event: 'ACCOUNT_DISABLED',
      settingKey: SettingsCatalog.actionDisableAccount,
    );
    return 'Tu cuenta esta pausada. Tu perfil queda oculto hasta que lo '
        'reactives desde Privacidad.';
  }

  /// Borra la cuenta de forma definitiva delegando en el flujo de sesion
  /// (que re-autentica y elimina auth + datos).
  Future<void> deleteAccount() async {
    await _repository.recordAudit(
      uid: _uid,
      event: 'ERASURE_REQUEST_CREATED',
      settingKey: SettingsCatalog.actionDeleteAccount,
    );
    await _onDeleteAccount();
  }

  Future<List<ConsentRecord>> loadConsentHistory() =>
      _repository.loadConsentHistory(_uid);

  Future<List<Map<String, dynamic>>> loadChangeHistory() =>
      _repository.loadAuditHistory(_uid);
}
