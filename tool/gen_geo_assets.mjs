// Genera los assets geográficos offline a partir del dataset de dr5hn
// (github.com/dr5hn/countries-states-cities-database, json/).
//
// Uso: node tool/gen_geo_assets.mjs <countries+states+cities.json> [--keep-names]
//
// Nombres de ciudad y coordenadas salen del MISMO fichero. Las coordenadas se
// buscan POR NOMBRE normalizado y se escriben en el orden de la lista de
// nombres, así que quedan alineadas índice a índice por construcción.
//
// --keep-names: conserva las listas YA publicadas (assets/geo/cities y
// countries.json) y solo regenera coords + nombres de país. Es lo que se usó
// para añadir las coordenadas: una descarga nueva de dr5hn cambia nombres
// ('Yangzhou' -> 'YangZhou'), quita condados de EEUU que ya había elegido
// gente y movería ciudades guardadas fuera de la lista válida.
//
// Salida:
//   assets/geo/countries.json          países (nombre, ISO2, bandera, región)
//   assets/geo/cities/<ISO2>.json      nombres de ciudad (deduplicados, ordenados)
//   assets/geo/coords/<ISO2>.json      ALINEADO índice a índice con cities:
//                                      [lat*100, lng*100] (enteros) o null
//   assets/geo/country_names.json      nombre normalizado -> ISO2 (inglés,
//                                      nativo, traducciones y alias)
//   functions/src/countryNames.ts      el mismo mapa para el backend
import { existsSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'fs';

const args = process.argv.slice(2);
const keepNames = args.includes('--keep-names');
const [datasetPath] = args.filter((a) => !a.startsWith('--'));
if (!datasetPath) {
  console.error(
    'Uso: node tool/gen_geo_assets.mjs <countries+states+cities.json> [--keep-names]');
  process.exit(1);
}
const dataset = JSON.parse(readFileSync(datasetPath, 'utf8'));

// Un nombre repetido en el mismo país (dos pueblos que se llaman igual en
// provincias distintas) solo tiene coordenadas si todas caen a menos de esto:
// si no, `null` y decide el geocodificador. Mejor sin centro que en el sitio
// equivocado.
const AMBIGUOUS_KM = 30;

// Alias que no vienen en las traducciones del dataset pero que SÍ escriben los
// geocodificadores de móviles en otros idiomas (catalán, euskera, gallego…).
const EXTRA_COUNTRY_ALIASES = {
  ES: ['Espanya', 'Espainia', 'Reino de España', 'Espana'],
  GB: ['Inglaterra', 'Reino Unido', 'UK', 'Great Britain', 'England', 'Scotland', 'Wales'],
  US: ['USA', 'Estados Unidos', 'EEUU', 'EE. UU.', 'EE.UU.', 'United States of America'],
  NL: ['Holanda', 'Holland'],
  DE: ['Deutschland'],
  CZ: ['Czech Republic', 'República Checa', 'Chequia'],
  TR: ['Turkey', 'Turquía', 'Türkiye'],
};

// --- Normalización: MISMA regla que `PlaceNames.normalize` (Dart), el backend
// y los scripts de Python. Si divergen, los nombres dejan de casar.
const DIACRITICS = {
  á: 'a', à: 'a', â: 'a', ä: 'a', ã: 'a', å: 'a', ā: 'a',
  é: 'e', è: 'e', ê: 'e', ë: 'e', ē: 'e',
  í: 'i', ì: 'i', î: 'i', ï: 'i', ī: 'i',
  ó: 'o', ò: 'o', ô: 'o', ö: 'o', õ: 'o', ø: 'o', ō: 'o',
  ú: 'u', ù: 'u', û: 'u', ü: 'u', ū: 'u',
  ñ: 'n', ç: 'c', ß: 'ss', œ: 'oe', æ: 'ae',
};

export function normalize(input) {
  const lower = String(input ?? '').toLowerCase().trim();
  if (!lower) return '';
  let out = '';
  for (const ch of lower) out += DIACRITICS[ch] ?? ch;
  return out.replace(/\s+/g, ' ').trim();
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const r = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}

/// Centro de un grupo de homónimos, o null si están demasiado separados.
function centroid(points) {
  if (points.length === 0) return null;
  for (let i = 0; i < points.length; i++) {
    for (let j = i + 1; j < points.length; j++) {
      if (
        haversineKm(points[i][0], points[i][1], points[j][0], points[j][1]) >
        AMBIGUOUS_KM
      ) {
        return null;
      }
    }
  }
  const lat = points.reduce((s, p) => s + p[0], 0) / points.length;
  const lng = points.reduce((s, p) => s + p[1], 0) / points.length;
  return [Math.round(lat * 100), Math.round(lng * 100)];
}

const outDir = 'assets/geo';
const citiesDir = `${outDir}/cities`;
const coordsDir = `${outDir}/coords`;
if (!keepNames) rmSync(citiesDir, { recursive: true, force: true });
rmSync(coordsDir, { recursive: true, force: true });
mkdirSync(citiesDir, { recursive: true });
mkdirSync(coordsDir, { recursive: true });

const countriesOut = [];
let withCoords = 0;
let ambiguous = 0;
let total = 0;

// Puntos por nombre NORMALIZADO y país: es la clave con la que busca el
// cliente, así que "Cadiz" y "Cádiz" comparten centro aunque el dataset traiga
// los dos.
const pointsByIso2 = new Map();
const namesByIso2 = new Map();
for (const country of dataset) {
  const iso2 = String(country.iso2 ?? '').toUpperCase();
  if (!iso2) continue;
  const pointsByKey = new Map();
  const seen = new Set();
  const cities = [];
  for (const state of country.states ?? []) {
    for (const city of state.cities ?? []) {
      const name = String(city.name ?? '').trim();
      if (!name) continue;
      const lat = Number.parseFloat(city.latitude);
      const lng = Number.parseFloat(city.longitude);
      const key = normalize(name);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        if (!pointsByKey.has(key)) pointsByKey.set(key, []);
        pointsByKey.get(key).push([lat, lng]);
      }
      const dedupe = name.toLowerCase();
      if (seen.has(dedupe)) continue;
      seen.add(dedupe);
      cities.push(name);
    }
  }
  cities.sort((a, b) => a.localeCompare(b));
  pointsByIso2.set(iso2, pointsByKey);
  namesByIso2.set(iso2, { country, cities });
}

/// Coordenadas en el MISMO orden que [cities]: alineadas por construcción.
function coordsFor(iso2, cities) {
  const pointsByKey = pointsByIso2.get(iso2) ?? new Map();
  return cities.map((name) => {
    const c = centroid(pointsByKey.get(normalize(name)) ?? []);
    total++;
    if (c) withCoords++;
    else ambiguous++;
    return c;
  });
}

if (keepNames) {
  // Se respetan los países y las ciudades publicados tal cual.
  const published = JSON.parse(readFileSync(`${outDir}/countries.json`, 'utf8'));
  for (const c of published) {
    const iso2 = String(c.iso2).toUpperCase();
    const file = `${citiesDir}/${iso2}.json`;
    const cities = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : [];
    writeFileSync(`${coordsDir}/${iso2}.json`, JSON.stringify(coordsFor(iso2, cities)));
  }
} else {
  for (const [iso2, { country, cities }] of namesByIso2) {
    writeFileSync(`${citiesDir}/${iso2}.json`, JSON.stringify(cities));
    writeFileSync(`${coordsDir}/${iso2}.json`, JSON.stringify(coordsFor(iso2, cities)));
    countriesOut.push({
      name: country.name,
      iso2,
      emoji: country.emoji || '',
      region: country.region || '',
      cityCount: cities.length,
    });
  }
  countriesOut.sort((a, b) => a.name.localeCompare(b.name));
  writeFileSync(`${outDir}/countries.json`, JSON.stringify(countriesOut));
}

// --- Nombres de país -> ISO2. Prioridad por pasadas: el nombre inglés (el del
// selector) manda sobre el nativo, el nativo sobre el español y el español
// sobre el resto de traducciones. Un choque DENTRO de una misma pasada deja la
// clave fuera: mejor no deducir el país que deducir el equivocado.
const names = {};
const decidedIn = {};
function addPass(pass, entries) {
  const local = {};
  const clash = new Set();
  for (const [raw, iso2] of entries) {
    const key = normalize(raw);
    if (!key) continue;
    if (key in local && local[key] !== iso2) clash.add(key);
    local[key] = iso2;
  }
  for (const [key, iso2] of Object.entries(local)) {
    if (clash.has(key)) continue;
    if (key in names) continue; // una pasada anterior manda
    names[key] = iso2;
    decidedIn[key] = pass;
  }
}
const up = (c) => String(c.iso2 ?? '').toUpperCase();
addPass('iso', dataset.map((c) => [up(c), up(c)]));
addPass('name', dataset.map((c) => [c.name, up(c)]));
addPass('extra', Object.entries(EXTRA_COUNTRY_ALIASES).flatMap(
  ([iso2, list]) => list.map((n) => [n, iso2])));
addPass('native', dataset.map((c) => [c.native ?? '', up(c)]));
addPass('es', dataset.map((c) => [c.translations?.es ?? '', up(c)]));
addPass('translations', dataset.flatMap((c) =>
  Object.values(c.translations ?? {}).map((n) => [n, up(c)])));

const sortedNames = Object.fromEntries(
  Object.entries(names).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
writeFileSync(`${outDir}/country_names.json`, JSON.stringify(sortedNames));

const ts = `// GENERADO por tool/gen_geo_assets.mjs — no editar a mano.
//
// Nombre de país NORMALIZADO (minúsculas, sin acentos, ver \`normalizePlace\`)
// -> ISO2. Es el mismo mapa que assets/geo/country_names.json: el backend lo
// usa para deducir \`countryIso2\` de quien solo tiene el nombre guardado.
export const COUNTRY_NAME_TO_ISO2: Readonly<Record<string, string>> = ${JSON.stringify(sortedNames)};
`;
writeFileSync('functions/src/countryNames.ts', ts);

console.log('Países:', keepNames ? 'conservados' : countriesOut.length);
console.log(`Ciudades: ${total} (con centro ${withCoords}, sin centro ${ambiguous})`);
console.log('Nombres de país:', Object.keys(sortedNames).length);
