"""Regresion offline de los backfills de geo: python -m unittest tool.test_backfill_geo

Nunca toca Firebase: la red se sustituye por un doble que sirve documentos de
mentira y apunta lo que se intentaria escribir.
"""
import contextlib
import importlib
import io
import json
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

geo_names = importlib.import_module("geo_names")
firestore_rest = importlib.import_module("firestore_rest")
backfill_country_iso2 = importlib.import_module("backfill_country_iso2")
backfill_travel_geo = importlib.import_module("backfill_travel_geo")

NOW = datetime(2026, 9, 25, 12, tzinfo=timezone.utc)


def doc(path, fields):
    return {"name": f"{firestore_rest.DOC_BASE}/{path}",
            "fields": firestore_rest.nested_fields(fields)}


class FakeNetwork:
    """Sirve `list`/`runQuery` y apunta los `:commit`."""

    def __init__(self, docs_by_collection):
        self.docs = docs_by_collection
        self.commits = []

    def __call__(self, request, timeout=None):
        url = request.full_url
        body = json.loads(request.data.decode()) if request.data else None
        if url.endswith(":commit"):
            self.commits.append(body)
            return io.StringIO(json.dumps({"writeResults": []}))
        if url.endswith(":runQuery"):
            collection = body["structuredQuery"]["from"][0]["collectionId"]
            rows = [{"document": d} for d in self.docs.get(collection, [])]
            return io.StringIO(json.dumps(rows))
        collection = url.split("/documents/", 1)[1].split("?", 1)[0]
        return io.StringIO(json.dumps({"documents": self.docs.get(collection, [])}))


def run(module, network, *args, **kwargs):
    output = io.StringIO()
    with patch.dict(os.environ, {"GTOKEN": "test-token"}), \
            patch.object(firestore_rest.urllib.request, "urlopen", network), \
            contextlib.redirect_stdout(output):
        summary = module.main(list(args), **kwargs)
    return summary, output.getvalue()


class GeoNamesTest(unittest.TestCase):
    def test_normalizacion_igual_que_la_app(self):
        self.assertEqual(geo_names.normalize("  Cádiz "), "cadiz")
        self.assertEqual(geo_names.normalize("El Puerto de Santa María"),
                         "el puerto de santa maria")

    def test_pais_por_nombre_en_cualquier_idioma(self):
        for name in ("España", "Spain", "Espanya", "Spanien", "Espagne"):
            self.assertEqual(geo_names.iso2_for_country_name(name), "ES", name)
        self.assertEqual(geo_names.iso2_for_country_name("Narnia"), "")

    def test_centro_de_ciudad_con_y_sin_acento(self):
        for city in ("Cádiz", "Cadiz"):
            lat, lng = geo_names.city_coordinates("ES", city)
            self.assertAlmostEqual(lat, 36.53, delta=0.02)
            self.assertAlmostEqual(lng, -6.29, delta=0.02)
        self.assertIsNone(geo_names.city_coordinates("ES", "Cadizz"))
        self.assertIsNone(geo_names.city_coordinates("US", "Springfield"))


class CountryIso2BackfillTest(unittest.TestCase):
    def network(self):
        return FakeNetwork({
            "discovery": [
                doc("discovery/catalan", {"currentCountryName": "Espanya"}),
                doc("discovery/ya", {"currentCountryName": "España",
                                     "countryIso2": "ES"}),
                doc("discovery/rara", {"currentCountryName": "Narnia"}),
            ],
            "seed_profiles": [
                doc("seed_profiles/mock_ana", {"currentCountryName": "España"}),
            ],
        })

    def test_dry_run_no_escribe(self):
        net = self.network()
        summary, output = run(backfill_country_iso2, net, "--dry-run")
        self.assertEqual(net.commits, [])
        output.encode("cp1252")  # La CLI se usa redirigida en Windows.
        self.assertEqual(summary["discovery"]["rellenar"], 1)
        self.assertEqual(summary["discovery"]["ya_tiene"], 1)
        self.assertEqual(summary["discovery"]["pais_desconocido"], 1)
        self.assertEqual(summary["seed_profiles"]["rellenar"], 1)
        self.assertIn('"countryIso2": "ES"', output)

    def test_escribe_solo_el_campo_que_falta(self):
        net = self.network()
        run(backfill_country_iso2, net)
        writes = [w for c in net.commits for w in c["writes"]]
        by_path = {w["update"]["name"].split("/documents/", 1)[1]: w
                   for w in writes}
        self.assertEqual(set(by_path), {"discovery/catalan",
                                        "seed_profiles/mock_ana"})
        disc = by_path["discovery/catalan"]
        self.assertEqual(disc["updateMask"]["fieldPaths"], ["countryIso2"])
        self.assertEqual(disc["update"]["fields"]["countryIso2"],
                         {"stringValue": "ES"})
        self.assertEqual(disc["currentDocument"], {"exists": True})
        self.assertEqual(
            by_path["seed_profiles/mock_ana"]["updateMask"]["fieldPaths"],
            ["currentCountryIso2"])


class TravelGeoBackfillTest(unittest.TestCase):
    def travel(self, uid, **travel):
        return doc(f"users/{uid}", {f"settings.travel.{k}": v
                                    for k, v in travel.items()})

    def network(self):
        future = (NOW + timedelta(days=10)).isoformat()
        past = (NOW - timedelta(days=1)).isoformat()
        return FakeNetwork({"users": [
            # Madrid -> Cadiz guardado por una version antigua: sin centro.
            self.travel("ana", active=True, iso2="ES", city="Cadiz",
                        country="Spain", until=future),
            # Registro aun mas antiguo: sin ISO2, pais en español.
            self.travel("leo", active=True, iso2="", city="Cádiz",
                        country="España", until=future),
            # Ya situado y con untilAt: nada que hacer.
            self.travel("eva", active=True, iso2="ES", city="Cadiz",
                        country="Spain", lat=36.53, lng=-6.29,
                        untilAt=NOW + timedelta(days=5)),
            # Caducado: se apaga conservando el destino.
            self.travel("old", active=True, iso2="ES", city="Cadiz",
                        country="Spain", until=past),
            # A un pais entero: sin centro por diseño.
            self.travel("pais", active=True, iso2="ES", city="",
                        country="Spain", until=future),
        ]})

    def test_dry_run_no_escribe(self):
        net = self.network()
        summary, output = run(backfill_travel_geo, net, "--dry-run", now=NOW)
        self.assertEqual(net.commits, [])
        output.encode("cp1252")
        self.assertEqual(summary["situar"], 2)
        self.assertEqual(summary["apagar"], 1)
        self.assertEqual(summary["al_dia"], 2, "eva y el viaje a un pais entero")
        self.assertNotIn("untilAt", summary)
        self.assertEqual(summary["escritos"], 0)

    def test_parches(self):
        net = self.network()
        run(backfill_travel_geo, net, now=NOW)
        writes = {w["update"]["name"].rsplit("/", 1)[1]: w
                  for c in net.commits for w in c["writes"]}
        self.assertNotIn("eva", writes)
        self.assertNotIn("pais", writes, "un viaje sin ciudad no tiene nada que situar")

        ana = writes["ana"]
        travel = ana["update"]["fields"]["settings"]["mapValue"]["fields"][
            "travel"]["mapValue"]["fields"]
        self.assertAlmostEqual(travel["lat"]["doubleValue"], 36.53, delta=0.02)
        self.assertAlmostEqual(travel["lng"]["doubleValue"], -6.29, delta=0.02)
        self.assertEqual(travel["geoSource"], {"stringValue": "asset"})
        # El centro va atado al destino para el que se resolvio.
        self.assertEqual(travel["geoCity"], {"stringValue": "Cadiz"})
        self.assertEqual(travel["geoIso2"], {"stringValue": "ES"})
        # Ya NO se añade untilAt: las versiones antiguas nunca lo reescriben y
        # una fecha fijada aqui acababa cortando el viaje semanas antes.
        self.assertNotIn("untilAt", travel)
        # Nunca se toca `active` ni el destino ni la fecha al situar.
        masks = set(ana["updateMask"]["fieldPaths"])
        self.assertNotIn("settings.travel.active", masks)
        self.assertNotIn("settings.travel.city", masks)
        self.assertNotIn("settings.travel.untilAt", masks)
        self.assertNotIn("settings.travel.until", masks)
        self.assertEqual(ana["currentDocument"], {"exists": True})

        self.assertIn("settings.travel.lat", writes["leo"]["updateMask"][
            "fieldPaths"], "sin ISO2 se deduce del nombre del pais")

        old = writes["old"]
        old_travel = old["update"]["fields"]["settings"]["mapValue"]["fields"][
            "travel"]["mapValue"]["fields"]
        self.assertEqual(old_travel["active"], {"booleanValue": False})
        self.assertEqual(old_travel["lat"], {"nullValue": None})
        # Tambien el `until` ISO: si se quedaba, reactivar desde una version
        # antigua o con seed_review_demo.py lo dejaba caducado otra vez.
        self.assertEqual(old_travel["until"], {"nullValue": None})
        self.assertEqual(old_travel["untilAt"], {"nullValue": None})
        self.assertNotIn("settings.travel.country",
                         old["updateMask"]["fieldPaths"],
                         "el destino se conserva para reactivarlo")


class TravelPlanTest(unittest.TestCase):
    """Casos sueltos de plan_travel_patch (mismas reglas que el backend)."""

    plan = staticmethod(backfill_travel_geo.plan_travel_patch)

    def test_manda_la_fecha_mas_tardia(self):
        # Version antigua que reactivo el viaje: `until` nuevo, `untilAt` viejo.
        action, _ = self.plan({
            "active": True, "iso2": "ES", "city": "", "country": "Spain",
            "untilAt": NOW - timedelta(days=3),
            "until": (NOW + timedelta(days=20)).isoformat(),
        }, NOW)
        self.assertEqual(action, "al_dia")

    def test_fecha_imposible_se_apaga(self):
        action, patch_ = self.plan({
            "active": True, "iso2": "ES", "city": "", "country": "Spain",
            "until": (NOW + timedelta(days=400)).isoformat(),
        }, NOW)
        self.assertEqual(action, "apagar")
        self.assertIsNone(patch_["settings.travel.until"])

    def test_centro_de_otra_ciudad_se_vuelve_a_situar(self):
        # La version antigua cambio de Cadiz a Barcelona sin tocar lat/lng.
        action, patch_ = self.plan({
            "active": True, "iso2": "ES", "city": "Barcelona",
            "country": "Spain", "lat": 36.5267, "lng": -6.2891,
            "geoCity": "Cadiz", "geoIso2": "ES",
            "until": (NOW + timedelta(days=20)).isoformat(),
        }, NOW)
        self.assertEqual(action, "situar")
        self.assertAlmostEqual(patch_["settings.travel.lat"], 41.39, delta=0.1)
        self.assertEqual(patch_["settings.travel.geoCity"], "Barcelona")

    def test_cuentas_de_revision(self):
        # COMPANION antes del arreglo: viaje de agosto ya pasado -> se apaga.
        action, _ = self.plan({
            "active": True, "city": "Madrid", "country": "Spain", "iso2": "ES",
            "until": "2026-09-07T11:18:30Z",
        }, NOW)
        self.assertEqual(action, "apagar")
        # Tal como las deja seed_review_demo.py --travel-spain: nada que hacer.
        action, patch_ = self.plan({
            "active": True, "iso2": "ES", "country": "España", "city": "",
            "until": None, "untilAt": None, "lat": None, "lng": None,
            "geoSource": "none",
        }, NOW)
        self.assertEqual((action, patch_), ("al_dia", None))


if __name__ == "__main__":
    unittest.main()
