import 'package:attra/src/features/ai_visual/domain/prompt_match_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptMatchRules.extract', () {
    test('extrae ojos, altura y personalidad del ejemplo del usuario', () {
      final PromptSignals s = PromptMatchRules.extract(
          'Me gustaría un chico alto, de ojos azules y moreno, que sea '
          'carismático y gracioso. Aventurero y le guste viajar!');
      expect(s.eyeColors, contains('blue'));
      expect(s.heightPref, HeightPref.tall);
      expect(s.keywords, contains('carismat'));
      expect(s.keywords, contains('gracios'));
      expect(s.keywords, contains('aventur'));
      expect(s.keywords, contains('viaj'));
      expect(s.hasStructured, isTrue);
    });

    test('detecta complexión atlética y altura baja', () {
      final PromptSignals s =
          PromptMatchRules.extract('chica atlética y bajita, deportista');
      expect(s.bodyTypes, contains('athletic'));
      expect(s.heightPref, HeightPref.short);
      expect(s.keywords, contains('deport'));
    });

    test('prompt sin señales queda vacío', () {
      final PromptSignals s = PromptMatchRules.extract('hola qué tal');
      expect(s.isEmpty, isTrue);
    });
  });

  group('PromptMatchRules.dataScore', () {
    final PromptSignals blueTallTraveler = PromptMatchRules.extract(
        'alto de ojos azules, aventurero y le gusta viajar');

    test('perfil que casa ojos+altura+interés puntúa alto', () {
      final double score = PromptMatchRules.dataScore(
        signals: blueTallTraveler,
        eyeColor: 'blue',
        heightCm: 185,
        profileText: 'me encanta viajar y la aventura',
      );
      expect(score, greaterThan(0.8));
    });

    test('perfil que no casa nada puntúa bajo', () {
      final double score = PromptMatchRules.dataScore(
        signals: blueTallTraveler,
        eyeColor: 'brown',
        heightCm: 165,
        profileText: 'me gusta leer en casa',
      );
      expect(score, lessThan(0.2));
    });

    test('campos ausentes no penalizan (los cubre la foto)', () {
      // Sin eyeColor ni heightCm declarados: solo cuenta lo que hay (interés).
      final double score = PromptMatchRules.dataScore(
        signals: blueTallTraveler,
        profileText: 'aventura y viajes por el mundo',
      );
      // Casó el interés (1 de 3 señales) → > 0 pero no perfecto.
      expect(score, greaterThan(0.0));
      expect(score, lessThan(0.5));
    });

    test('señales vacías → score 0', () {
      final PromptSignals empty = PromptMatchRules.extract('hola');
      expect(
        PromptMatchRules.dataScore(signals: empty, profileText: 'lo que sea'),
        0.0,
      );
    });
  });
}
