/// Tipo de control de un rasgo de perfil.
enum TraitType { singleSelect, multiSelect, text, number }

/// Opcion de un select.
class TraitOption {
  const TraitOption(this.value, this.label);
  final String value;
  final String label;
}

/// Definicion de UN rasgo completable del perfil. Vive en
/// `users/{uid}.[group].[field]` (p.ej. group='profile', field='orientation').
///
/// `sensitive=true` => opcional, NUNCA inferido/autorrellenado, oculto por
/// defecto, no cuenta para el Profile Strength y solo se publica/usa con
/// consentimiento explicito.
class ProfileTraitDefinition {
  const ProfileTraitDefinition({
    required this.key,
    required this.sectionKey,
    required this.label,
    required this.type,
    required this.group,
    required this.field,
    this.options = const <TraitOption>[],
    this.sensitive = false,
  });

  final String key; // unico en el catalogo
  final String sectionKey;
  final String label;
  final TraitType type;
  final String
      group; // profile | appearance | lifestyle | style | preferences | origin
  final String field;
  final List<TraitOption> options;
  final bool sensitive;

  bool get isSelect =>
      type == TraitType.singleSelect || type == TraitType.multiSelect;
}

/// Seccion de rasgos.
class ProfileSection {
  const ProfileSection({
    required this.key,
    required this.title,
    required this.definitions,
  });
  final String key;
  final String title;
  final List<ProfileTraitDefinition> definitions;
}
