/// Resumen minimo de un perfil para listas (matches, chats, likes): solo lo
/// necesario para pintar una fila (nombre + foto).
class ProfileSummary {
  const ProfileSummary({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String photoUrl;

  static const ProfileSummary unknown = ProfileSummary(
    uid: '',
    displayName: 'Alguien',
    photoUrl: '',
  );

  ProfileSummary copyWith({String? uid, String? displayName, String? photoUrl}) {
    return ProfileSummary(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
