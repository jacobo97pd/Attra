/// Comparación de nombres de sitio (ciudades y países) PURA, sin assets ni
/// Flutter, para que la lógica de dominio (feed, viajes) pueda usarla y
/// probarla sin `rootBundle`.
///
/// La MISMA regla está copiada en tool/gen_geo_assets.mjs, en el backend
/// (functions/src/travel.ts) y en los scripts de Python: si una de las copias
/// cambia, los nombres dejan de casar entre el dataset y lo guardado.
class PlaceNames {
  const PlaceNames._();

  /// Normaliza para comparar: minúsculas, sin acentos, espacios colapsados.
  static String normalize(String input) {
    final String lower = input.toLowerCase().trim();
    if (lower.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (final int codeUnit in lower.runes) {
      final String ch = String.fromCharCode(codeUnit);
      buffer.write(_diacritics[ch] ?? ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clave de ciudad para comparar pese al idioma y a los acentos.
  ///
  /// Solo bajar a minúsculas (lo que hacía el feed) dejaba 'Cadiz' — la grafía
  /// del dataset, que es lo que guarda el selector del viaje — distinto de
  /// 'Cádiz', que es como lo escriben los perfiles: la gente de Cádiz no
  /// contaba como "de la ciudad de destino" justo en el viaje del que se quejó
  /// el usuario.
  static String canonCity(String raw) {
    final String s = normalize(raw);
    return _cityAliases[s] ?? s;
  }

  static const Map<String, String> _cityAliases = <String, String>{
    'roma': 'rome',
    'milano': 'milan',
    'londres': 'london',
    'lisboa': 'lisbon',
    'munchen': 'munich',
    'napoles': 'naples',
    'napoli': 'naples',
    'florencia': 'florence',
    'firenze': 'florence',
    'venecia': 'venice',
    'venezia': 'venice',
    'torino': 'turin',
    'atenas': 'athens',
    'athina': 'athens',
    'praga': 'prague',
    'praha': 'prague',
    'viena': 'vienna',
    'wien': 'vienna',
    'varsovia': 'warsaw',
    'warszawa': 'warsaw',
    'bruselas': 'brussels',
    'bruxelles': 'brussels',
    'brussel': 'brussels',
    'amberes': 'antwerp',
    'antwerpen': 'antwerp',
    'ginebra': 'geneva',
    'geneve': 'geneva',
    'copenhague': 'copenhagen',
    'kobenhavn': 'copenhagen',
    'estocolmo': 'stockholm',
    'moscu': 'moscow',
    'estambul': 'istanbul',
    'nueva york': 'new york city',
    'new york': 'new york city',
    'nueva delhi': 'new delhi',
    'pekin': 'beijing',
    'tokio': 'tokyo',
    'ciudad de mexico': 'mexico city',
    'seville': 'sevilla',
    'la coruna': 'a coruna',
    'coruna': 'a coruna',
    'gerona': 'girona',
    'lerida': 'lleida',
  };
}

const Map<String, String> _diacritics = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
  'œ': 'oe',
  'æ': 'ae',
};
