import 'package:attra/src/features/profile/data/discovery_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifica que los ajustes de Privacidad/Ubicación se reflejan en el payload
/// público de discovery (lo que ven los demás en el feed).
void main() {
  Map<String, dynamic> userWith(Map<String, dynamic> settings) =>
      <String, dynamic>{
        'displayName': 'Ana',
        'onboardingCompleted': true,
        'profileCompleted': true,
        'profile': <String, dynamic>{
          'currentCity': 'Madrid',
          'currentCountryName': 'Spain',
          'bio': 'hola',
        },
        'location': <String, dynamic>{
          'latitude': 40.4168,
          'longitude': -3.7038,
        },
        'settings': settings,
      };

  group('DiscoveryPublisher visibilidad', () {
    test('por defecto publica ciudad, distancia y actividad visibles', () {
      final Map<String, dynamic> out =
          DiscoveryPublisher.buildPayload('u1', userWith(<String, dynamic>{}));
      expect(out['currentCity'], 'Madrid');
      expect(out['showDistance'], true);
      expect(out['showActiveStatus'], true);
    });

    test('location.showOnProfile=false oculta la ciudad (no el país)', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{'location.showOnProfile': false}),
      );
      expect(out['currentCity'], '');
      expect(out['currentCountryName'], 'Spain');
    });

    test('privacy.showDistance=false / showActiveStatus=false marcan banderas',
        () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{
          'privacy.showDistance': false,
          'privacy.showActiveStatus': false,
        }),
      );
      expect(out['showDistance'], false);
      expect(out['showActiveStatus'], false);
    });

    test('location.precision precisa redondea a 2 decimales (~1km)', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{'location.precision': 'precise'}),
      );
      final Map<String, dynamic> geo = out['geo'] as Map<String, dynamic>;
      expect(geo['lat'], 40.42);
      expect(geo['lng'], -3.70);
    });

    test('integrations.instagram publica el @usuario si está activado', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{
          'integrations.instagram': true,
          'integrations.instagramHandle': 'ana.dev',
        }),
      );
      expect(out['instagram'], 'ana.dev');
    });

    test('integrations.instagram desactivado no publica handle', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{
          'integrations.instagram': false,
          'integrations.instagramHandle': 'ana.dev',
        }),
      );
      expect(out.containsKey('instagram'), false);
    });

    test('location.precision aproximada difumina a 1 decimal (~11km)', () {
      final Map<String, dynamic> out = DiscoveryPublisher.buildPayload(
        'u1',
        userWith(<String, dynamic>{'location.precision': 'approximate'}),
      );
      final Map<String, dynamic> geo = out['geo'] as Map<String, dynamic>;
      expect(geo['lat'], 40.4);
      expect(geo['lng'], -3.7);
    });
  });
}
