import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:flutter_test/flutter_test.dart';

/// La ciudad y el país los escribía SOLO el selector manual del onboarding.
/// Al hacer que las coordenadas se refresquen solas, quedaron desfasados
/// respecto a ellas — y eso es peor que tenerlo todo rancio a la vez: cruzas
/// una frontera, tus coordenadas dicen Lisboa y tu país sigue diciendo España,
/// la regla de país te enseña españoles y la de radio los descarta a todos.
/// Encima dejas de ser visible para los de alrededor.
void main() {
  group('Un sitio solo sirve si trae país', () {
    test('con país es utilizable', () {
      expect(
        const ResolvedPlace(
          city: 'Valencia',
          countryName: 'España',
          countryIso2: 'ES',
        ).isUsable,
        isTrue,
      );
    });

    test('sin país NO es utilizable aunque traiga ciudad', () {
      // Sobrescribir con media verdad deja el perfil incoherente: ciudad nueva
      // y país viejo es exactamente el estado que rompe los dos filtros.
      expect(
        const ResolvedPlace(city: 'Valencia', countryName: '', countryIso2: '')
            .isUsable,
        isFalse,
      );
    });

    test('un país en blancos no cuenta como país', () {
      expect(
        const ResolvedPlace(
          city: 'Valencia',
          countryName: '   ',
          countryIso2: '',
        ).isUsable,
        isFalse,
      );
    });
  });

  group('Cuándo merece la pena reescribir', () {
    test('no se escribe si el sitio es el mismo', () {
      // Cada escritura arrastra una republicación de `discovery` por el trigger
      // de backend, y el geocodificador de iOS está limitado por tasa.
      expect(
        shouldUpdatePlace(
          resolved: const ResolvedPlace(
            city: 'Madrid',
            countryName: 'España',
            countryIso2: 'ES',
          ),
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isFalse,
      );
    });

    test('las mayúsculas y los espacios no cuentan como cambio', () {
      expect(
        shouldUpdatePlace(
          resolved: const ResolvedPlace(
            city: 'madrid ',
            countryName: ' España',
            countryIso2: 'ES',
          ),
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isFalse,
      );
    });

    test('mudarse de ciudad sí se escribe', () {
      expect(
        shouldUpdatePlace(
          resolved: const ResolvedPlace(
            city: 'Valencia',
            countryName: 'España',
            countryIso2: 'ES',
          ),
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isTrue,
      );
    });

    test('cruzar una frontera sí se escribe', () {
      expect(
        shouldUpdatePlace(
          resolved: const ResolvedPlace(
            city: 'Lisboa',
            countryName: 'Portugal',
            countryIso2: 'PT',
          ),
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isTrue,
      );
    });

    test('si no se pudo resolver NO se toca nada', () {
      // Sin red o con el geocodificador pasado de tasa se conserva el sitio
      // anterior entero: borrar la ciudad buena sería empeorar el perfil.
      expect(
        shouldUpdatePlace(
          resolved: null,
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isFalse,
      );
    });

    test('un resultado sin país tampoco pisa lo que había', () {
      expect(
        shouldUpdatePlace(
          resolved:
              const ResolvedPlace(city: 'X', countryName: '', countryIso2: ''),
          currentCity: 'Madrid',
          currentCountryName: 'España',
        ),
        isFalse,
      );
    });
  });
}
