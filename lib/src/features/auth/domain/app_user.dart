import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.onboardingCompleted,
    required this.profileCompleted,
    required this.profileCompletionPercent,
    required this.isBot,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool onboardingCompleted;
  final bool profileCompleted;
  final int profileCompletionPercent;
  final bool isBot;

  factory AppUser.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};
    return AppUser(
      uid: (data['uid'] as String?) ?? document.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      onboardingCompleted: _asBool(data['onboardingCompleted']),
      profileCompleted: _asBool(data['profileCompleted']),
      profileCompletionPercent: _asInt(data['profileCompletionPercent']),
      isBot: _asBool(data['isBot']),
    );
  }

  static bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
