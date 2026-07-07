import 'package:attra/src/features/date_plans/domain/date_plan_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasEnoughConversation', () {
    test('bajo el umbral no propone', () {
      expect(DatePlanRules.hasEnoughConversation(0), isFalse);
      expect(DatePlanRules.hasEnoughConversation(5), isFalse);
    });
    test('en/por encima del umbral sí', () {
      expect(DatePlanRules.hasEnoughConversation(6), isTrue);
      expect(DatePlanRules.hasEnoughConversation(20), isTrue);
    });
  });

  group('isValidZone', () {
    test('acepta zonas razonables', () {
      expect(DatePlanRules.isValidZone('Chamberí'), isTrue);
      expect(DatePlanRules.isValidZone('Malasaña'), isTrue);
    });
    test('rechaza vacío/corto/nulo', () {
      expect(DatePlanRules.isValidZone(''), isFalse);
      expect(DatePlanRules.isValidZone('a'), isFalse);
      expect(DatePlanRules.isValidZone(null), isFalse);
    });
    test('rechaza coordenadas exactas (privacidad)', () {
      expect(DatePlanRules.isValidZone('40.4168, -3.7038'), isFalse);
    });
  });

  group('commonCategories', () {
    test('detecta interés compartido explícito (café + arte)', () {
      final List<PlanCategory> cats = DatePlanRules.commonCategories(
        aInterests: <String>['Café', 'Arte contemporáneo'],
        bInterests: <String>['tomar café', 'museos'],
        chatMessages: <String>[],
      );
      expect(cats, contains(PlanCategory.cafe));
      expect(cats, contains(PlanCategory.cultura));
    });

    test('la conversación aporta señal aunque el perfil no', () {
      final List<PlanCategory> cats = DatePlanRules.commonCategories(
        aInterests: <String>[],
        bInterests: <String>[],
        chatMessages: <String>['¿te apetece que vayamos a cenar unas tapas?'],
      );
      expect(cats, contains(PlanCategory.comida));
    });

    test('normaliza tildes (música)', () {
      final List<PlanCategory> cats = DatePlanRules.commonCategories(
        aInterests: <String>['musica en directo'],
        bInterests: <String>['Música'],
        chatMessages: <String>[],
      );
      expect(cats, contains(PlanCategory.musica));
    });

    test('sin señales devuelve vacío', () {
      final List<PlanCategory> cats = DatePlanRules.commonCategories(
        aInterests: <String>['programación'],
        bInterests: <String>['finanzas'],
        chatMessages: <String>['hola qué tal'],
      );
      expect(cats, isEmpty);
    });
  });

  group('recommendedPlanTypes', () {
    test('siempre devuelve 3 y con carriles variados', () {
      final List<PlanCategory> rec =
          DatePlanRules.recommendedPlanTypes(<PlanCategory>[PlanCategory.cafe]);
      expect(rec.length, 3);
      final Set<PlanTier> tiers = rec.map((PlanCategory c) => c.tier).toSet();
      expect(tiers.length, greaterThanOrEqualTo(2));
    });

    test('sin señales cae a default seguro empezando por café', () {
      final List<PlanCategory> rec =
          DatePlanRules.recommendedPlanTypes(<PlanCategory>[]);
      expect(rec.length, 3);
      expect(rec.first, PlanCategory.cafe);
    });

    test('prioriza lo común pero no repite carril', () {
      final List<PlanCategory> rec = DatePlanRules.recommendedPlanTypes(
        <PlanCategory>[PlanCategory.cafe, PlanCategory.paseo],
      );
      // cafe y paseo son ambos "safe": no deben ocupar los 3 huecos.
      expect(rec.length, 3);
      expect(rec.where((PlanCategory c) => c.tier == PlanTier.safe).length, 1);
    });
  });

  group('passesPlaceQuality', () {
    test('filtra rating bajo', () {
      expect(
          DatePlanRules.passesPlaceQuality(rating: 3.8, reviewCount: 500),
          isFalse);
    });
    test('filtra pocas reseñas', () {
      expect(
          DatePlanRules.passesPlaceQuality(rating: 4.7, reviewCount: 5),
          isFalse);
    });
    test('acepta buen sitio', () {
      expect(
          DatePlanRules.passesPlaceQuality(rating: 4.5, reviewCount: 820),
          isTrue);
    });
    test('sin datos no bloquea (rating/reviews null)', () {
      expect(DatePlanRules.passesPlaceQuality(), isTrue);
    });
  });
}
