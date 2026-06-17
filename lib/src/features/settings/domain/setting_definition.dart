/// Modelo dirigido por definiciones para la "Settings Platform".
///
/// Cada ajuste se describe con una [SettingDefinition] (metadatos: tipo,
/// scope, base juridica, si requiere suscripcion/permiso/region, etc.). La UI
/// y la logica de "valor efectivo" se derivan de estos metadatos, de forma que
/// anadir o cambiar un ajuste no requiere tocar la UI: solo el catalogo.
///
/// Aterrizado del informe de privacidad de apps de citas: cada setting lleva
/// setting_key, section_key, data_type, scope, default_value, requires_*,
/// legal_basis, consent_required, user_visible, editable, destructive,
/// audit_level y provenance.
library;

/// Tipo de dato del valor de un ajuste.
enum SettingType { boolean, enumeration, text, integer }

/// Ambito del ajuste. Importa para no confundir un toggle de cuenta con un
/// permiso real del dispositivo (ver "permission mismatch" del informe).
enum SettingScope { account, device, platform, region }

/// Nivel de auditoria de un cambio de ajuste.
enum AuditLevel { none, low, standard, high }

/// Base juridica (RGPD) asociada al tratamiento que habilita el ajuste.
enum LegalBasis { none, consent, contract, legitimateInterest, legalObligation }

/// Origen del ultimo valor de un ajuste.
enum SettingProvenance { user, system, migration, support, policy }

/// Una opcion concreta para un ajuste de tipo [SettingType.enumeration].
class SettingOption {
  const SettingOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Definicion declarativa de un ajuste individual.
class SettingDefinition {
  const SettingDefinition({
    required this.key,
    required this.sectionKey,
    required this.type,
    required this.label,
    required this.description,
    this.scope = SettingScope.account,
    this.defaultValue,
    this.options = const <SettingOption>[],
    this.requiresSubscription = false,
    this.requiresOsPermission,
    this.requiresRegion,
    this.requiresAgeGate = false,
    this.legalBasis = LegalBasis.none,
    this.consentPurpose,
    this.optOutSemantics = false,
    this.userVisible = true,
    this.editable = true,
    this.destructive = false,
    this.auditLevel = AuditLevel.standard,
    this.legalUrl,
  });

  /// Identificador unico estable (setting_key). Es la clave de persistencia.
  final String key;

  /// Seccion a la que pertenece (section_key).
  final String sectionKey;

  final SettingType type;
  final String label;
  final String description;
  final SettingScope scope;

  /// Valor por defecto cuando el usuario nunca lo ha tocado.
  final Object? defaultValue;

  /// Opciones (solo para [SettingType.enumeration]).
  final List<SettingOption> options;

  /// Requiere plan premium para poder activarse.
  final bool requiresSubscription;

  /// Permiso del SO del que depende (p.ej. 'location', 'biometric').
  /// Si el permiso real no esta concedido, el valor efectivo queda bloqueado
  /// (permission mismatch).
  final String? requiresOsPermission;

  /// Codigo de region donde el ajuste es relevante (p.ej. 'US' para
  /// sale/share opt-out). Null = global.
  final String? requiresRegion;

  final bool requiresAgeGate;

  final LegalBasis legalBasis;

  /// Si esta presente, cambiar este ajuste registra un consentimiento con
  /// esta finalidad en el consent ledger.
  final String? consentPurpose;

  /// True cuando el toggle expresa una EXCLUSION (opt-out): el valor `true`
  /// significa "no quiero". Afecta solo a la copy de ayuda.
  final bool optOutSemantics;

  final bool userVisible;
  final bool editable;
  final bool destructive;
  final AuditLevel auditLevel;

  /// Enlace a documentacion legal contextual.
  final String? legalUrl;

  bool get consentRequired => consentPurpose != null;

  /// Casteo seguro del valor crudo de Firestore al tipo declarado, cayendo al
  /// default si el tipo no coincide o el valor es nulo.
  Object? coerce(Object? raw) {
    switch (type) {
      case SettingType.boolean:
        if (raw is bool) return raw;
        if (raw is String) return raw.toLowerCase() == 'true';
        return defaultValue ?? false;
      case SettingType.enumeration:
        if (raw is String && options.any((SettingOption o) => o.value == raw)) {
          return raw;
        }
        return defaultValue;
      case SettingType.text:
        if (raw is String) return raw;
        return defaultValue ?? '';
      case SettingType.integer:
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        if (raw is String) return int.tryParse(raw) ?? defaultValue;
        return defaultValue ?? 0;
    }
  }
}

/// Una accion (no es un valor: es un boton, p.ej. "Exportar datos",
/// "Eliminar cuenta"). Se renderiza como CTA, no como toggle.
class SettingsAction {
  const SettingsAction({
    required this.key,
    required this.label,
    required this.description,
    this.destructive = false,
    this.requiresReauth = false,
    this.icon,
  });

  final String key;
  final String label;
  final String description;
  final bool destructive;

  /// Requiere re-autenticacion reforzada (delete/export/credenciales).
  final bool requiresReauth;

  /// Nombre del icono Material (resuelto en la UI).
  final String? icon;
}

/// Una seccion del menu de ajustes con sus definiciones y acciones.
class SettingsSection {
  const SettingsSection({
    required this.key,
    required this.title,
    required this.icon,
    required this.description,
    this.definitions = const <SettingDefinition>[],
    this.actions = const <SettingsAction>[],
  });

  final String key;
  final String title;

  /// Nombre del icono Material (resuelto en la UI).
  final String icon;
  final String description;
  final List<SettingDefinition> definitions;
  final List<SettingsAction> actions;
}
