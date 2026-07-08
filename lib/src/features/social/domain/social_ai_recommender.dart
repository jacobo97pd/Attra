import 'friend_group.dart';

/// Punto de integración para la IA social (futuro). Deja la FORMA lista para
/// enchufar recomendaciones reales (Vertex/reglas) sin tocar la UI ni los
/// servicios: hoy se puede inyectar una implementación por reglas y mañana una
/// con IA, detrás del mismo contrato.
///
/// NO implementado todavía: es solo el contrato.
abstract class SocialAiRecommender {
  /// Recomienda grupos para el usuario a partir de su ciudad + intereses.
  Future<List<FriendGroup>> recommendGroups({
    required String uid,
    required String city,
    required List<String> interests,
    int limit,
  });

  /// Sugiere planes reales para un grupo (tipo de plan + zona; sin inventar
  /// lugares — los verifica Places, igual que Attra Plans).
  Future<List<String>> suggestGroupPlans({
    required String groupId,
    required List<String> interests,
    String city,
  });

  /// Genera rompehielos para el chat de un grupo.
  Future<List<String>> groupIcebreakers({
    required String groupId,
    required List<String> memberInterests,
  });

  /// Compatibilidad social del grupo [0..1]: cómo de afín es el conjunto de
  /// miembros por intereses/objetivos.
  Future<double> groupAffinity({required String groupId});
}
