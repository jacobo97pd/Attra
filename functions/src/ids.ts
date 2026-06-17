/// IDs deterministas. DEBEN coincidir byte a byte con el cliente Dart
/// (`lib/src/features/match/domain/pair_id.dart`).
///
/// CRITICO: usamos comparacion nativa de strings (`<=`), que en JS compara por
/// unidades de codigo UTF-16, igual que `String.compareTo` de Dart. NO usar
/// `localeCompare` (es sensible a locale y produciria ids distintos).

export function pairId(a: string, b: string): string {
  return a <= b ? `${a}_${b}` : `${b}_${a}`;
}

export function directedId(fromUid: string, toUid: string): string {
  return `${fromUid}_${toUid}`;
}
