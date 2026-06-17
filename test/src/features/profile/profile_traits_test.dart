import 'package:attra/src/features/profile/data/discovery_publisher.dart';
import 'package:attra/src/features/profile/domain/profile_completion.dart';
import 'package:attra/src/features/profile/domain/profile_trait.dart';
import 'package:attra/src/features/profile/domain/profile_traits_catalog.dart';
import 'package:attra/src/features/profile/domain/profile_visibility.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileTraitsCatalog', () {
    test('todas las keys son únicas', () {
      final List<String> keys = ProfileTraitsCatalog.all
          .map((ProfileTraitDefinition d) => d.key)
          .toList();
      expect(keys.length, keys.toSet().length);
    });

    test(
        'los campos sensibles incluyen orientación/etnia/religión/política/'
        'cannabis/drogas', () {
      final Set<String> s = ProfileTraitsCatalog.sensitiveKeys;
      expect(
          s,
          containsAll(<String>[
            'sexualOrientation',
            'ethnicity',
            'religion',
            'politics',
            'cannabis',
            'drugs'
          ]));
    });
  });

  group('isUsableTraitValue', () {
    test('prefer_not_to_say NO es utilizable (matching/filtros)', () {
      expect(isUsableTraitValue('prefer_not_to_say'), isFalse);
    });
    test('vacío/null no es utilizable', () {
      expect(isUsableTraitValue(''), isFalse);
      expect(isUsableTraitValue(null), isFalse);
      expect(isUsableTraitValue(<String>[]), isFalse);
    });
    test('valor real sí es utilizable', () {
      expect(isUsableTraitValue('straight'), isTrue);
      expect(isUsableTraitValue(180), isTrue);
    });
  });

  group('ProfileVisibility.effectiveFor (defaults)', () {
    test('no sensible => visible y utilizable por defecto', () {
      final ProfileTraitDefinition def = ProfileTraitsCatalog.byKey('zodiac')!;
      final FieldVisibility v = const ProfileVisibility().effectiveFor(def);
      expect(v.visibleInProfile, isTrue);
      expect(v.useForMatching, isTrue);
    });
    test('sensible => OPT-IN (oculto por defecto)', () {
      final ProfileTraitDefinition def =
          ProfileTraitsCatalog.byKey('ethnicity')!;
      final FieldVisibility v = const ProfileVisibility().effectiveFor(def);
      expect(v.visibleInProfile, isFalse);
      expect(v.useForMatching, isFalse);
    });
  });

  group('DiscoveryPublisher.buildPayload', () {
    Map<String, dynamic> baseUser({
      Map<String, dynamic>? profileExtra,
      Map<String, dynamic>? origin,
      Map<String, dynamic>? visibilityFields,
    }) {
      return <String, dynamic>{
        'email': 'secreto@correo.com',
        'displayName': 'Javier Legal Google', // nombre Auth
        'photoUrl': 'https://x/p.jpg',
        'profile': <String, dynamic>{
          'visibleName': 'Bella Hadid', // nombre elegido
          'gender': 'female',
          'bio': 'hola',
          'orientation': <String>['lesbian'], // sensible
          ...?profileExtra,
        },
        'preferences': <String, dynamic>{
          'interestedIn': <String>['female']
        },
        if (origin != null) 'origin': origin,
        if (visibilityFields != null)
          'profileVisibility': <String, dynamic>{'fields': visibilityFields},
      };
    }

    test('NO publica email ni el nombre de Auth si hay nombre elegido', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('u1', baseUser());
      expect(out.containsKey('email'), isFalse);
      expect(out['displayName'], 'Bella Hadid');
    });

    test('publica edad calculada desde fecha de nacimiento', () {
      final DateTime birthDate = DateTime.utc(1992, 1, 2);
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        baseUser(profileExtra: <String, dynamic>{
          'birthDate': Timestamp.fromDate(birthDate),
        }),
      );

      expect(out['age'], _expectedAge(birthDate));
    });

    test('NO publica campo sensible sin consentimiento (orientación)', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('u1', baseUser());
      expect(out.containsKey('orientation'), isFalse);
    });

    test('SÍ publica sensible si visibleInProfile=true', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        baseUser(visibilityFields: <String, dynamic>{
          'sexualOrientation': <String, dynamic>{
            'visibleInProfile': true,
            'useForMatching': true,
            'useForFilters': true,
          },
        }),
      );
      expect(out['orientation'], <String>['lesbian']);
    });

    test('valor prefer_not_to_say no se publica aunque esté visible', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        baseUser(
          origin: <String, dynamic>{'ethnicity': 'prefer_not_to_say'},
          visibilityFields: <String, dynamic>{
            'ethnicity': <String, dynamic>{
              'visibleInProfile': true,
              'useForMatching': true,
              'useForFilters': true,
            },
          },
        ),
      );
      expect(out.containsKey('ethnicity'), isFalse);
    });

    test('etnicidad va a filterTraits SOLO con consentimiento useForFilters',
        () {
      // Sin consentimiento de filtros => no filtrable.
      final Map<String, dynamic> sinConsent = DiscoveryPublisher.buildPayload(
        'u1',
        baseUser(origin: <String, dynamic>{'ethnicity': 'hispanic_latino'}),
      );
      expect(sinConsent.containsKey('filterTraits'), isFalse);

      // Con useForFilters => entra en filterTraits.
      final Map<String, dynamic> conConsent = DiscoveryPublisher.buildPayload(
        'u1',
        baseUser(
          origin: <String, dynamic>{'ethnicity': 'hispanic_latino'},
          visibilityFields: <String, dynamic>{
            'ethnicity': <String, dynamic>{
              'visibleInProfile': false,
              'useForMatching': false,
              'useForFilters': true,
            },
          },
        ),
      );
      final Map<String, dynamic> ft =
          (conConsent['filterTraits'] as Map).cast<String, dynamic>();
      expect(ft['ethnicity'], 'hispanic_latino');
      // useForFilters NO implica mostrarlo en el perfil.
      expect(conConsent.containsKey('ethnicity'), isFalse);
    });

    test('geo redondeado (no exacto) y verified', () {
      final Map<String, dynamic> data = baseUser()
        ..['location'] = <String, dynamic>{
          'latitude': 40.416775,
          'longitude': -3.703790,
        }
        ..['verification'] = <String, dynamic>{
          'liveSelfiePublicPhotoUrl': 'https://x/selfie.jpg',
        };
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('u1', data);
      final Map<String, dynamic> geo =
          (out['geo'] as Map).cast<String, dynamic>();
      expect(geo['lat'], 40.42); // redondeado a 2 decimales
      expect(geo['lng'], -3.70);
      expect(out['verified'], true);
    });

    test('perfil antiguo sin traits ni visibility no rompe', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('u1', <String, dynamic>{
        'profile': <String, dynamic>{'gender': 'male'}
      });
      expect(out['uid'], 'u1');
      expect(out['gender'], 'male');
      expect(out['isBot'], false);
    });
  });

  group('ProfileStrength (ProfileCompletionCalculator)', () {
    test('no penaliza por completar campos sensibles', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'profile': <String, dynamic>{'bio': 'x'},
      };
      final int before = ProfileCompletionCalculator.calculate(base).percent;
      final Map<String, dynamic> withSensitive = <String, dynamic>{
        'profile': <String, dynamic>{
          'bio': 'x',
          'orientation': <String>['gay'],
          'religion': 'catholic',
          'politics': 'left',
        },
        'lifestyle': <String, dynamic>{
          'cannabis': 'sometimes',
          'drugs': 'never'
        },
        'origin': <String, dynamic>{'ethnicity': 'multiracial'},
      };
      final int after =
          ProfileCompletionCalculator.calculate(withSensitive).percent;
      expect(after, before); // los sensibles no suman ni restan
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
