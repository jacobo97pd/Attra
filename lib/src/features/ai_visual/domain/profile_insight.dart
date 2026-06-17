/// Sugerencia para mejorar el perfil (de getProfileInsights). NO contiene datos
/// sensibles ni embeddings: solo consejos accionables.
class ProfileInsight {
  const ProfileInsight({
    required this.id,
    required this.severity,
    required this.text,
  });

  final String id;
  final String severity; // high | medium | info
  final String text;

  factory ProfileInsight.fromMap(Map<String, dynamic> map) {
    return ProfileInsight(
      id: (map['id'] as String?) ?? '',
      severity: (map['severity'] as String?) ?? 'info',
      text: (map['text'] as String?) ?? '',
    );
  }
}
