import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeedProfile.fromMap', () {
    test('calcula edad desde birthDate si age no viene materializada', () {
      final DateTime birthDate = DateTime.utc(1992, 1, 2);
      final SeedProfile profile = SeedProfile.fromMap(
        'u1',
        <String, dynamic>{
          'displayName': 'Ada',
          'profile': <String, dynamic>{
            'birthDate': Timestamp.fromDate(birthDate),
          },
        },
      );

      expect(profile.age, _expectedAge(birthDate));
    });

    test('respeta age explicita por encima de birthDate', () {
      final SeedProfile profile = SeedProfile.fromMap(
        'u1',
        <String, dynamic>{
          'displayName': 'Ada',
          'age': 31,
          'profile': <String, dynamic>{
            'birthDate': Timestamp.fromDate(DateTime.utc(1992, 1, 2)),
          },
        },
      );

      expect(profile.age, 31);
    });
  });
}

int _expectedAge(DateTime birthDate) {
  final DateTime now = DateTime.now();
  final DateTime localBirthDate = birthDate.toLocal();
  int age = now.year - localBirthDate.year;
  final bool hasBirthdayPassed = now.month > localBirthDate.month ||
      (now.month == localBirthDate.month && now.day >= localBirthDate.day);
  if (!hasBirthdayPassed) age -= 1;
  return age;
}
