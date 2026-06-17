// Genera los assets geográficos offline a partir de los datasets de dr5hn.
// Uso: node tool/gen_geo_assets.mjs <countries.json> <countries+cities.json>
// Salida: assets/geo/countries.json  +  assets/geo/cities/<ISO2>.json
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'fs';

const [, , countriesPath, citiesPath] = process.argv;
const countriesMeta = JSON.parse(readFileSync(countriesPath, 'utf8'));
const countriesCities = JSON.parse(readFileSync(citiesPath, 'utf8'));

// name -> {iso2, emoji, region}
const metaByName = new Map();
for (const c of countriesMeta) {
  metaByName.set(c.name, {
    iso2: c.iso2,
    emoji: c.emoji || '',
    region: c.region || '',
  });
}

const outDir = 'assets/geo';
const citiesDir = `${outDir}/cities`;
rmSync(citiesDir, { recursive: true, force: true });
mkdirSync(citiesDir, { recursive: true });

const countriesOut = [];
let matched = 0;
let unmatched = [];

for (const entry of countriesCities) {
  const meta = metaByName.get(entry.name);
  if (!meta || !meta.iso2) {
    unmatched.push(entry.name);
    continue;
  }
  matched++;
  const iso2 = meta.iso2.toUpperCase();

  // Dedupe + sort cities
  const seen = new Set();
  const cities = [];
  for (const raw of entry.cities || []) {
    const name = String(raw).trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    cities.push(name);
  }
  cities.sort((a, b) => a.localeCompare(b));

  writeFileSync(`${citiesDir}/${iso2}.json`, JSON.stringify(cities));
  countriesOut.push({
    name: entry.name,
    iso2,
    emoji: meta.emoji,
    region: meta.region,
    cityCount: cities.length,
  });
}

countriesOut.sort((a, b) => a.name.localeCompare(b.name));
writeFileSync(`${outDir}/countries.json`, JSON.stringify(countriesOut));

console.log('Paises con ciudades:', matched);
console.log('Sin match (omitidos):', unmatched.length, unmatched.slice(0, 10));
console.log('countries.json escrito con', countriesOut.length, 'paises');
