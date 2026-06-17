/// Date Builder (Fase 7): convierte preferencias de plan en una PROPUESTA
/// estructurada para empujar el match hacia una cita. PURO/testeable. No reserva
/// nada ni usa APIs externas: solo compone un plan + nota que alimenta el flujo
/// de propuesta de cita ya existente (`sendDateProposal`).
library;

enum PlanType {
  cafe('cafe', 'un café'),
  paseo('paseo', 'un paseo'),
  cena('cena', 'una cena'),
  copa('copa', 'una copa'),
  helado('helado', 'un helado'),
  museo('museo', 'una visita a un museo'),
  concierto('concierto', 'un concierto'),
  tranquilo('tranquilo', 'un plan tranquilo'),
  espontaneo('espontaneo', 'algo espontáneo');

  const PlanType(this.key, this.phrase);
  final String key;
  final String phrase;
}

enum DateMoment {
  manana('manana', 'por la mañana'),
  tarde('tarde', 'por la tarde'),
  noche('noche', 'por la noche'),
  finde('finde', 'el fin de semana');

  const DateMoment(this.key, this.phrase);
  final String key;
  final String phrase;
}

enum DateBudget {
  gratis('gratis', 'sin gastar'),
  barato('barato', 'barato'),
  medio('medio', 'algo intermedio'),
  especial('especial', 'algo especial');

  const DateBudget(this.key, this.phrase);
  final String key;
  final String phrase;
}

enum DateDuration {
  m30('30min', '30 minutos'),
  h1('1h', '1 hora'),
  h2('2h', '2 horas'),
  sinPrisa('sin_prisa', 'sin prisa');

  const DateDuration(this.key, this.phrase);
  final String key;
  final String phrase;
}

enum DateVibe {
  tranquilo('tranquilo', 'tranquilo'),
  divertido('divertido', 'divertido'),
  elegante('elegante', 'elegante'),
  casual('casual', 'casual'),
  romantico('romantico', 'romántico sin intensidad');

  const DateVibe(this.key, this.phrase);
  final String key;
  final String phrase;
}

class DatePreferences {
  const DatePreferences({
    this.planType,
    this.moment,
    this.budget,
    this.duration,
    this.vibe,
  });

  final PlanType? planType;
  final DateMoment? moment;
  final DateBudget? budget;
  final DateDuration? duration;
  final DateVibe? vibe;

  bool get isComplete =>
      planType != null &&
      moment != null &&
      budget != null &&
      duration != null &&
      vibe != null;

  DatePreferences copyWith({
    PlanType? planType,
    DateMoment? moment,
    DateBudget? budget,
    DateDuration? duration,
    DateVibe? vibe,
  }) {
    return DatePreferences(
      planType: planType ?? this.planType,
      moment: moment ?? this.moment,
      budget: budget ?? this.budget,
      duration: duration ?? this.duration,
      vibe: vibe ?? this.vibe,
    );
  }
}

/// Propuesta resultante: un lugar sugerido + una nota redactada.
class DatePlanSuggestion {
  const DatePlanSuggestion({
    required this.placeName,
    required this.note,
    required this.summary,
  });

  /// Sugerencia de "lugar" (tipo de sitio, no un sitio real).
  final String placeName;

  /// Nota amable lista para la propuesta (editable por el usuario).
  final String note;

  /// Frase-resumen del encaje (para mostrar en la UI antes de proponer).
  final String summary;
}

class DateBuilder {
  const DateBuilder._();

  /// Lugar sugerido por tipo de plan (genérico, no un sitio real).
  static const Map<PlanType, String> _placeFor = <PlanType, String>{
    PlanType.cafe: 'una cafetería con encanto',
    PlanType.paseo: 'un paseo por el centro',
    PlanType.cena: 'un sitio para cenar con calma',
    PlanType.copa: 'un bar con buen ambiente',
    PlanType.helado: 'una heladería',
    PlanType.museo: 'un museo o exposición',
    PlanType.concierto: 'un concierto o música en directo',
    PlanType.tranquilo: 'un sitio tranquilo',
    PlanType.espontaneo: 'lo que nos apetezca sobre la marcha',
  };

  /// Compone la sugerencia a partir de las preferencias. Si faltan campos, usa
  /// defaults suaves para no bloquear (pero la UI puede exigir completar).
  static DatePlanSuggestion suggest(DatePreferences p) {
    final PlanType plan = p.planType ?? PlanType.cafe;
    final DateMoment moment = p.moment ?? DateMoment.tarde;
    final DateBudget budget = p.budget ?? DateBudget.barato;
    final DateDuration duration = p.duration ?? DateDuration.h1;
    final DateVibe vibe = p.vibe ?? DateVibe.casual;

    final String place = _placeFor[plan] ?? 'un plan sencillo';
    final String durationPhrase =
        duration == DateDuration.sinPrisa ? 'sin prisa' : 'de ${duration.phrase}';

    final String summary =
        'Un plan ${vibe.phrase} ${moment.phrase}, ${budget.phrase} y $durationPhrase. '
        'Buena opción: ${plan.phrase} en $place.';

    final String note =
        '¿Te apetece ${plan.phrase} ${moment.phrase}? Lo veo $durationPhrase y '
        '${budget.phrase}, con un punto ${vibe.phrase}.';

    return DatePlanSuggestion(
      placeName: _capitalize(place),
      note: note,
      summary: summary,
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
