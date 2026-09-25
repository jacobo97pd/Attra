import '../../profile/domain/profile_trait.dart';
import '../../social/domain/intent_mode.dart';

/// "Me interesan" (`users/{uid}.preferences.interestedIn`): a quién quiere
/// conocer alguien para CITAS. Puro/testeable (sin Flutter).
///
/// POR QUÉ EXISTE FUERA DEL ONBOARDING: el onboarding solo lo pregunta en
/// citas/ambas, así que quien se registraba en amistad o grupos lo dejaba vacío.
/// Al pasarse luego a citas nada volvía a pedirlo y no había dónde editarlo, y
/// la regla permisiva de GenderMatching ("vacío = quiere a todo el mundo") lo
/// convertía en bisexual por omisión EN LOS DOS SENTIDOS: un hombre hetero que
/// venía de amistad veía hombres y mujeres y, además, salía en el feed de los
/// hombres gays. Por eso lo reutilizan el selector de modo (que ya no deja
/// entrar en citas sin elegirlo) y el editor permanente del perfil.
class InterestedIn {
  const InterestedIn._();

  /// Las tres casillas que sabe expresar `interestedIn` (las mismas del
  /// onboarding y de GenderMatching.interestBuckets).
  static const List<TraitOption> options = <TraitOption>[
    TraitOption('female', 'Mujer'),
    TraitOption('male', 'Hombre'),
    TraitOption('non_binary', 'No binario'),
  ];

  /// Destino en Firestore, como rasgo para reutilizar la vía que ya existe
  /// (SessionController.setProfileTrait → UserRepository.setProfileTrait): esa
  /// escritura lleva los campos que exigen las reglas, re-sincroniza discovery
  /// y recarga el usuario, así que el feed propio y el de los demás cambian ya.
  static const ProfileTraitDefinition trait = ProfileTraitDefinition(
    key: 'interestedIn',
    sectionKey: 'preferences',
    label: 'Me interesan',
    type: TraitType.multiSelect,
    group: 'preferences',
    field: 'interestedIn',
    options: options,
  );

  /// ¿Hay que pedirlo antes de usar [mode]? Solo cuando el modo incluye el
  /// canal de citas (dating/both) y no hay nada elegido: en amistad y grupos el
  /// género no filtra (FeedFilter solo lo mira con solape de citas).
  static bool requiredFor(IntentMode mode, Iterable<String> current) =>
      mode.channels.contains(SocialChannel.dating) &&
      !current.any((String v) => v.trim().isNotEmpty);

  /// Texto legible de lo elegido ("Mujer, Hombre"). Vacío si no hay nada.
  static String describe(Iterable<String> values) {
    String label(String code) {
      for (final TraitOption o in options) {
        if (o.value == code) return o.label;
      }
      return code;
    }

    return values
        .where((String v) => v.trim().isNotEmpty)
        .map(label)
        .join(', ');
  }
}

/// Resultado de [switchIntentModeWithInterest].
enum IntentSwitchOutcome {
  /// Nada que hacer: mismo modo y no faltaba "Me interesan".
  unchanged,

  /// El usuario cerró "Me interesan" sin elegir: NO se cambia de modo.
  cancelled,

  /// Se guardó "Me interesan" (y el modo, si cambiaba) o solo el modo.
  saved,
}

/// Cambia de modo exigiendo "Me interesan" cuando el modo nuevo incluye citas y
/// no hay nada elegido. Separado de la pantalla para poder probar la regla sin
/// montar el HomeShell entero.
///
/// "Me interesan" se guarda ANTES que el modo: si la segunda escritura fallara,
/// lo peor es tener la preferencia puesta sin haber cambiado de modo, nunca
/// estar en citas con la lista vacía (que es justo el fallo que se arregla).
/// Si el usuario re-confirma su modo actual de citas con la lista vacía (los
/// que ya estaban así antes de este arreglo) también se le pide.
Future<IntentSwitchOutcome> switchIntentModeWithInterest({
  required IntentMode current,
  required IntentMode chosen,
  required List<String> interestedIn,
  required Future<List<String>?> Function() askInterestedIn,
  required Future<void> Function(List<String> values) saveInterestedIn,
  required Future<void> Function(IntentMode mode) saveMode,
}) async {
  final bool needsInterest = InterestedIn.requiredFor(chosen, interestedIn);
  if (chosen == current && !needsInterest) return IntentSwitchOutcome.unchanged;
  if (needsInterest) {
    final List<String> picked = (await askInterestedIn() ?? const <String>[])
        .where((String v) => v.trim().isNotEmpty)
        .toList(growable: false);
    if (picked.isEmpty) return IntentSwitchOutcome.cancelled;
    await saveInterestedIn(picked);
  }
  if (chosen != current) await saveMode(chosen);
  return IntentSwitchOutcome.saved;
}
