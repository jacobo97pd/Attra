/// Formateo de precios COHERENTE con lo que devuelve la tienda.
///
/// StoreKit y Play devuelven el precio ya formateado y localizado para el
/// escaparate del usuario (`$179.99`, `179,99 €`, `¥19,800`…). Ese formato NO
/// tiene por qué coincidir con el idioma de la app: un usuario con la app en
/// español y cuenta de App Store en EE. UU. ve `$179.99`.
///
/// Por eso el precio por unidad NO se puede formatear por nuestra cuenta: si lo
/// hacemos con convención española junto a un precio de tienda en convención
/// estadounidense sale la incoherencia real que se vio en producción:
///
///   $179.99 / año        <- de la tienda
///   Equivale a 15,00 $   <- generado por la app  ❌
///
/// [repriceLike] resuelve esto reescribiendo el importe DENTRO de la cadena de
/// la tienda, conservando su símbolo, su posición y sus separadores.
library;

/// Devuelve [storePrice] con su importe sustituido por [newValue],
/// conservando exactamente el formato original.
///
/// ```dart
/// repriceLike(r'$179.99', 15)      // => r'$15.00'
/// repriceLike('179,99 €', 15)      // => '15,00 €'
/// repriceLike('¥19,800', 1650)     // => '¥1,650'
/// ```
///
/// Devuelve `null` si no se reconoce ningún número en [storePrice], para que
/// el llamante decida qué mostrar en lugar de inventarse un formato.
String? repriceLike(String storePrice, double newValue) {
  if (storePrice.isEmpty || !newValue.isFinite || newValue < 0) return null;

  // Bloque numérico completo, incluidos separadores de miles y decimales.
  // Se admiten espacios finos/duros porque algunas locales los usan como
  // separador de millares (p. ej. fr-FR: "1 234,56").
  final RegExpMatch? match =
      RegExp(r'\d[\d  .,\s]*\d|\d').firstMatch(storePrice);
  if (match == null) return null;
  final String raw = match.group(0)!;

  // Decimales: solo cuenta como separador decimal el que va seguido de 1 o 2
  // dígitos AL FINAL. Así "¥19,800" (miles) no se confunde con "19,80".
  final RegExpMatch? tail = RegExp(r'([.,])(\d{1,2})$').firstMatch(raw);
  final String decimalSep = tail?.group(1) ?? '';
  final int decimals = tail?.group(2)?.length ?? 0;

  // Separador de millares: el otro carácter de agrupación presente, si lo hay.
  String groupSep = '';
  for (final String candidate in <String>['.', ',', ' ', ' ', ' ']) {
    if (candidate == decimalSep) continue;
    if (raw.contains(candidate)) {
      groupSep = candidate;
      break;
    }
  }

  final String fixed = newValue.toStringAsFixed(decimals);
  final int dot = fixed.indexOf('.');
  final String intPart = dot < 0 ? fixed : fixed.substring(0, dot);
  final String fracPart = dot < 0 ? '' : fixed.substring(dot + 1);

  final String groupedInt =
      groupSep.isEmpty ? intPart : _group(intPart, groupSep);
  final String rebuilt =
      fracPart.isEmpty ? groupedInt : '$groupedInt$decimalSep$fracPart';

  return storePrice.replaceRange(match.start, match.end, rebuilt);
}

/// Precio mensual equivalente de una suscripción anual, con el MISMO formato
/// que el precio anual de la tienda. `null` si no se puede calcular.
String? monthlyEquivalentOf(String storeYearlyPrice, double rawYearlyPrice) {
  if (!rawYearlyPrice.isFinite || rawYearlyPrice <= 0) return null;
  return repriceLike(storeYearlyPrice, rawYearlyPrice / 12);
}

String _group(String digits, String separator) {
  if (digits.length <= 3) return digits;
  final StringBuffer out = StringBuffer();
  final int lead = digits.length % 3;
  if (lead > 0) out.write(digits.substring(0, lead));
  for (int i = lead; i < digits.length; i += 3) {
    if (out.isNotEmpty) out.write(separator);
    out.write(digits.substring(i, i + 3));
  }
  return out.toString();
}
