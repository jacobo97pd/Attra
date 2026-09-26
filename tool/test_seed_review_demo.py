"""Regresion offline del payload de revision: python -m unittest tool.test_seed_review_demo."""
import contextlib
from datetime import datetime, timedelta
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse


def load_seed():
    spec = importlib.util.spec_from_file_location(
        "seed_review_demo", Path(__file__).with_name("seed_review_demo.py")
    )
    module = importlib.util.module_from_spec(spec)
    # Importar y simular nunca requiere credenciales reales.
    with patch.dict(os.environ, {}, clear=True):
        spec.loader.exec_module(module)
    return module


class ReviewDemoSeedTest(unittest.TestCase):
    def setUp(self):
        self.seed = load_seed()
        self.uid = "review_test_uid"
        self.env = patch.dict(os.environ, {
            "DEMO_STAMP": "2026-08-04T10:00:00Z",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def run_seed(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.seed.main(["--uid", self.uid, *args])
        return output.getvalue()

    def test_dry_run_prepares_profile_pro_likes_and_chats_without_network(self):
        with patch.object(self.seed.urllib.request, "urlopen") as network:
            output = self.run_seed("--dry-run")
        network.assert_not_called()
        output.encode("cp1252")  # La CLI se usa tambien redirigida en Windows.
        rows = [json.loads(line) for line in output.splitlines()
                if line.startswith('{')]
        documents = {}
        for row in rows:
            documents.setdefault(row["path"], {}).update(row["fields"])

        user = documents[f"users/{self.uid}"]
        profile = user["profile"]["mapValue"]["fields"]
        self.assertEqual(profile["gender"], {"stringValue": "male"})
        self.assertEqual(profile["birthDate"]["timestampValue"],
                         "1995-05-20T00:00:00+00:00")
        self.assertEqual(user["onboardingCompleted"], {"booleanValue": True})
        self.assertEqual(user["profileCompleted"], {"booleanValue": True})
        settings = user["settings"]["mapValue"]["fields"]
        self.assertEqual(settings["tutorial.completed"], {"booleanValue": True})
        self.assertEqual(user["subscriptionTier"], {"stringValue": "pro"})
        self.assertNotIn("aiVisualConsent", user)

        discovery = documents[f"discovery/{self.uid}"]
        self.assertEqual(discovery["age"], {"integerValue": "31"})
        self.assertEqual(discovery["currentCity"], {"stringValue": "Madrid"})
        self.assertEqual(discovery["gender"], profile["gender"])
        self.assertIn("interestedIn", discovery)
        self.assertIn("photos", discovery)
        self.assertNotIn("email", discovery)
        self.assertNotIn("orientation", discovery)
        self.assertEqual(discovery["geo"]["mapValue"]["fields"]["lat"],
                         {"doubleValue": 40.42})

        entitlement = documents[f"userEntitlements/{self.uid}"]
        self.assertEqual(entitlement["tier"], {"stringValue": "pro"})
        self.assertEqual(entitlement["isLifetime"], {"booleanValue": True})
        self.assertEqual(entitlement["features"]["arrayValue"]["values"], [])
        self.assertEqual(entitlement["expiresAt"], {"nullValue": None})

        for other in self.seed.LIKED_ME:
            like = documents[f"likes/{other}_{self.uid}"]
            self.assertEqual(like["status"], {"stringValue": "active"})
            self.assertIn("timestampValue", like["createdAt"])

        for other, messages in self.seed.MATCHED:
            mid = "_".join(sorted([self.uid, other]))
            self.assertIn(f"matches/{mid}", documents)
            chat = documents[f"chats/{mid}"]
            previous = ""
            for index, (sender, _) in enumerate(messages):
                msg = documents[f"chats/{mid}/messages/demo_{index:02d}"]
                self.assertEqual(msg["senderId"],
                                 {"stringValue": sender or self.uid})
                timestamp = msg["createdAt"]["timestampValue"]
                self.assertGreater(timestamp, previous)
                previous = timestamp
            self.assertEqual(chat["lastMessageAt"]["timestampValue"], previous)
        self.assertTrue(all(not any(uid in path for path in documents)
                            for uid in self.seed.FEED_ONLY))

    def test_preflight_and_rest_requests_run_entirely_offline(self):
        self.seed.TOKEN = "offline-placeholder"
        requests = []

        def fake_urlopen(request, timeout):
            requests.append(request)
            if request.get_method() == "POST":
                self.assertTrue(request.full_url.endswith('/documents:commit'))
                writes = json.loads(request.data)['writes']
                self.assertGreaterEqual(len(writes), 20)
                names = [write['update']['name'] for write in writes]
                self.assertEqual(len(names), len(set(names)))
                user = next(write for write in writes
                            if write['update']['name'].endswith('/users/' + self.uid))
                # Actualiza solo hojas: no borra consentimientos/ajustes ajenos.
                masks = user['updateMask']['fieldPaths']
                self.assertIn('settings.`tutorial.completed`', masks)
                self.assertNotIn('settings', masks)
                self.assertNotIn('profile', masks)
                self.assertNotIn('consentRecords', masks)
                self.assertEqual(request.get_header('Authorization'),
                                 'Bearer offline-placeholder')
                return io.BytesIO(b'{}')
            if "/matches/" in request.full_url:
                # Cuenta limpia: ningun mock de LIKED_ME tiene match previo.
                raise urllib.error.HTTPError(request.full_url, 404, "missing", {}, None)
            fields = {"isBot": {"booleanValue": True},
                      "photoUrl": {"stringValue": "https://example.test/photo"},
                      "displayName": {"stringValue": "Demo"}}
            return io.BytesIO(json.dumps({"fields": fields}).encode())

        with patch.object(self.seed.urllib.request, "urlopen", fake_urlopen):
            self.run_seed()
        methods = [request.get_method() for request in requests]
        # users + 8 seed_profiles + un match por cada mock de LIKED_ME.
        reads = 9 + len(self.seed.LIKED_ME)
        self.assertEqual(methods[:reads], ["GET"] * reads)
        self.assertEqual(methods[reads:], ["POST"])

    def test_missing_mock_aborts_before_any_write(self):
        self.seed.TOKEN = "offline-placeholder"
        requests = []

        def missing_mock(request, timeout):
            requests.append(request)
            if "/seed_profiles/" in request.full_url:
                raise urllib.error.HTTPError(request.full_url, 404, "missing", {}, None)
            return io.BytesIO(b'{"fields": {}}')

        with patch.object(self.seed.urllib.request, "urlopen", missing_mock):
            with self.assertRaisesRegex(SystemExit, "seed_mock_profiles.py"):
                self.run_seed()
        self.assertTrue(all(request.get_method() == "GET" for request in requests))

    def test_keep_profile_only_updates_subscription_fields_on_user(self):
        with patch.dict(os.environ, {"DEMO_KEEP_PROFILE": "1"}):
            output = self.run_seed("--dry-run")
        rows = [json.loads(line) for line in output.splitlines()
                if line.startswith('{')]
        user_rows = [row for row in rows if row["path"] == f"users/{self.uid}"]
        self.assertEqual(len(user_rows), 1)
        self.assertEqual(set(user_rows[0]["fields"]),
                         {"subscriptionTier", "hasActiveSubscription"})
        self.assertFalse(any(row["path"].startswith("discovery/") for row in rows))

    def test_check_only_never_writes(self):
        self.seed.TOKEN = 'offline-placeholder'
        with patch.object(self.seed, 'require_document', return_value={
            'isBot': {'booleanValue': True},
            'photoUrl': {'stringValue': 'https://example.test/photo'},
            'displayName': {'stringValue': 'Demo'},
            'storiesEnabled': {'booleanValue': True},
        }), patch.object(self.seed, 'find_document', return_value=None), \
                patch.object(self.seed.urllib.request, 'urlopen') as network:
            output = self.run_seed('--check-only')
        network.assert_not_called()
        self.assertIn('storiesEnabled=True', output)
        self.assertIn('No se ha escrito', output)
        self.assertFalse(self.seed.PENDING_WRITES)

    def test_refresh_stories_keeps_profile_chats_and_normal_expiry(self):
        output = self.run_seed('--dry-run', '--stories-only')
        rows = [json.loads(line) for line in output.splitlines()
                if line.startswith('{')]
        self.assertEqual(len(rows), 8)
        owners = set()
        for row in rows:
            self.assertTrue(row['path'].startswith('stories/review_demo_'))
            fields = row['fields']
            owners.add(fields['ownerUid']['stringValue'])
            self.assertEqual(fields['mediaType'], {'stringValue': 'image'})
            self.assertEqual(fields['visibility'], {'stringValue': 'discovery'})
            self.assertEqual(fields['status'], {'stringValue': 'active'})
            self.assertIn('demostracion', fields['caption']['stringValue'])
            created = datetime.fromisoformat(fields['createdAt']['timestampValue'])
            expires = datetime.fromisoformat(fields['expiresAt']['timestampValue'])
            self.assertEqual(expires - created, timedelta(hours=72))
        self.assertTrue(set(self.seed.FEED_ONLY).issubset(owners))

    def test_real_peer_chat_can_be_opened_from_both_accounts(self):
        peer = 'other_review_account'
        output = self.run_seed('--dry-run', '--peer-uid', peer,
                               '--travel-spain', '--keep-profile')
        rows = [json.loads(line) for line in output.splitlines()
                if line.startswith('{')]
        documents = {row['path']: row['fields'] for row in rows}
        chat_id = '_'.join(sorted([peer, self.uid]))
        chat = documents['chats/' + chat_id]
        users = [value['stringValue']
                 for value in chat['users']['arrayValue']['values']]
        self.assertEqual(set(users), {peer, self.uid})
        self.assertEqual(documents['chats/' + chat_id + '/messages/demo_00']['senderId'],
                         {'stringValue': peer})
        user_rows = [row for row in rows if row['path'] == 'users/' + self.uid]
        self.assertTrue(all('profile' not in row['fields'] for row in user_rows))
        travel = next(row['fields']['settings']['mapValue']['fields']['travel']
                      for row in user_rows if 'settings' in row['fields'])
        self.assertEqual(travel['mapValue']['fields']['active'], {'booleanValue': True})
        # La cuenta compañera tambien viaja (las notas dicen "Ambas").
        peer_rows = [row for row in rows if row['path'] == 'users/' + peer
                     and 'settings' in row['fields']]
        self.assertEqual(len(peer_rows), 1)
        peer_travel = peer_rows[0]['fields']['settings']['mapValue']['fields'][
            'travel']['mapValue']['fields']
        self.assertEqual(peer_travel['iso2'], {'stringValue': 'ES'})
        self.assertEqual(peer_travel['until'], {'nullValue': None})

    def test_travel_spain_clears_old_end_date_and_center(self):
        # La cuenta COMPANION tenia un `until` de agosto ya pasado. Con la
        # mascara de hojas, resembrar dejaba esa fecha (el barrido lo apagaba
        # otra vez) y un centro viejo medía el viaje "a Espana" desde otra
        # ciudad.
        self.seed.TOKEN = 'offline-placeholder'
        commits = []
        fields = {'isBot': {'booleanValue': True},
                  'onboardingCompleted': {'booleanValue': True},
                  'profileCompleted': {'booleanValue': True},
                  'photoUrl': {'stringValue': 'https://example.test/photo'},
                  'displayName': {'stringValue': 'Demo'}}

        def fake_urlopen(request, timeout):
            if request.get_method() == 'POST':
                commits.append(json.loads(request.data))
                return io.BytesIO(b'{}')
            if '/matches/' in request.full_url:
                raise urllib.error.HTTPError(request.full_url, 404, 'missing', {}, None)
            return io.BytesIO(json.dumps({'fields': fields}).encode())

        peer = 'other_review_account'
        with patch.object(self.seed.urllib.request, 'urlopen', fake_urlopen):
            self.run_seed('--keep-profile', '--travel-spain', '--peer-uid', peer)
        writes = {w['update']['name'].rsplit('/documents/', 1)[1]: w
                  for w in commits[0]['writes']}
        for uid in (self.uid, peer):
            write = writes['users/' + uid]
            masks = set(write['updateMask']['fieldPaths'])
            for leaf in ('until', 'untilAt', 'lat', 'lng', 'geoCity', 'geoIso2'):
                self.assertIn(f'settings.travel.{leaf}', masks, (uid, leaf))
            travel = write['update']['fields']['settings']['mapValue']['fields'][
                'travel']['mapValue']['fields']
            for leaf in ('until', 'untilAt', 'lat', 'lng'):
                self.assertEqual(travel[leaf], {'nullValue': None}, (uid, leaf))
            self.assertEqual(travel['geoSource'], {'stringValue': 'none'})
            self.assertEqual(travel['city'], {'stringValue': ''})
            # La app recorta a 500: el documento dice lo mismo que se aplica.
            self.assertEqual(write['update']['fields']['preferences']['mapValue'][
                'fields']['maxDistanceKm'], {'integerValue': '500'})
            # Nunca se sustituye el mapa entero (conserva otros ajustes).
            self.assertNotIn('settings.travel', masks)
            self.assertNotIn('settings', masks)

    def test_check_only_travel_spain_flags_expired_trip_and_free_peer(self):
        self.seed.TOKEN = 'offline-placeholder'
        peer = 'other_review_account'
        seed_fields = {'isBot': {'booleanValue': True},
                       'photoUrl': {'stringValue': 'https://example.test/photo'},
                       'displayName': {'stringValue': 'Demo'},
                       'onboardingCompleted': {'booleanValue': True},
                       'profileCompleted': {'booleanValue': True}}

        def travel_doc(**travel):
            typed = {k: self.seed.to_value(v) for k, v in travel.items()}
            return {'settings': {'mapValue': {'fields': {
                'travel': {'mapValue': {'fields': typed}}}}}}

        docs = {
            # Viaje bien sembrado: sin fecha, sin centro.
            f'users/{self.uid}': travel_doc(active=True, iso2='ES',
                                            country='España', city='',
                                            until=None, untilAt=None),
            f'userEntitlements/{self.uid}': {
                'tier': {'stringValue': 'pro'},
                'isLifetime': {'booleanValue': True}},
            # El de COMPANION antes del arreglo: `until` de agosto ya pasado.
            f'users/{peer}': travel_doc(active=True, iso2='ES', country='Spain',
                                        city='Madrid',
                                        until='2026-09-07T11:18:30Z'),
        }

        def find(path):
            return docs.get(path)

        with patch.object(self.seed, 'require_document', return_value=seed_fields), \
                patch.object(self.seed, 'find_document', side_effect=find), \
                patch.object(self.seed.urllib.request, 'urlopen') as network:
            with self.assertRaises(SystemExit) as raised:
                self.run_seed('--check-only', '--travel-spain', '--peer-uid', peer)
        network.assert_not_called()
        message = str(raised.exception)
        self.assertIn(f'{peer}: viaje caducado', message)
        self.assertIn(f'{peer}: sin plan de pago vigente', message)
        self.assertNotIn(f'{self.uid}:', message)
        self.assertFalse(self.seed.PENDING_WRITES)

        # Arreglado (sin fecha y con plan), la comprobacion pasa.
        docs[f'users/{peer}'] = docs[f'users/{self.uid}']
        docs[f'userEntitlements/{peer}'] = docs[f'userEntitlements/{self.uid}']
        with patch.object(self.seed, 'require_document', return_value=seed_fields), \
                patch.object(self.seed, 'find_document', side_effect=find):
            output = self.run_seed('--check-only', '--travel-spain', '--peer-uid', peer)
        self.assertIn('Modo viajes a Espana: OK', output)

    def test_missing_real_peer_aborts_before_commit(self):
        self.seed.TOKEN = 'offline-placeholder'
        fields = {'isBot': {'booleanValue': True},
                  'photoUrl': {'stringValue': 'https://example.test/photo'},
                  'displayName': {'stringValue': 'Demo'}}
        def existing(path):
            if path == 'users/other_review_account':
                raise SystemExit('Falta cuenta de prueba')
            return fields
        with patch.object(self.seed, 'require_document', side_effect=existing), \
                patch.object(self.seed, 'find_document', return_value=None), \
                patch.object(self.seed.urllib.request, 'urlopen') as network:
            with self.assertRaisesRegex(SystemExit, 'Falta cuenta'):
                self.run_seed('--peer-uid', 'other_review_account')
        network.assert_not_called()
        self.assertFalse(self.seed.PENDING_WRITES)

    def test_old_match_with_liked_me_mock_aborts_before_any_write(self):
        # Ronda anterior: el revisor respondio a Maria y deshizo el match. El
        # backend trata ese match como terminal ('blocked'), asi que re-sembrar
        # su like dejaba en la bandeja una tarjeta que no se podia responder.
        self.seed.TOKEN = 'offline-placeholder'
        fields = {'isBot': {'booleanValue': True},
                  'photoUrl': {'stringValue': 'https://example.test/photo'},
                  'displayName': {'stringValue': 'Demo'}}
        stale = {self.seed.pair_id(self.uid, 'mock_t_maria'): 'unmatched',
                 self.seed.pair_id(self.uid, 'mock_t_carmen'): 'active'}

        def old_matches(path):
            collection, _, doc_id = path.partition('/')
            if collection == 'matches' and doc_id in stale:
                return {'status': {'stringValue': stale[doc_id]}}
            return None

        with patch.object(self.seed, 'require_document', return_value=fields), \
                patch.object(self.seed, 'find_document', side_effect=old_matches), \
                patch.object(self.seed.urllib.request, 'urlopen') as network:
            with self.assertRaises(SystemExit) as raised:
                self.run_seed()
        message = str(raised.exception)
        self.assertIn('mock_t_maria (unmatched)', message)
        self.assertIn('mock_t_carmen (active)', message)
        self.assertIn(f'reset_mock_feed.py --uid {self.uid} '
                      '--only mock_t_maria mock_t_carmen', message)
        self.assertNotIn('mock_t_laura', message)
        network.assert_not_called()
        self.assertFalse(self.seed.PENDING_WRITES)

    def test_find_document_reads_missing_docs_as_none(self):
        self.seed.TOKEN = 'offline-placeholder'

        def missing(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 404, 'missing', {}, None)

        with patch.object(self.seed.urllib.request, 'urlopen', missing):
            self.assertIsNone(self.seed.find_document('matches/a_b'))

        def denied(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 403, 'denied', {}, None)

        with patch.object(self.seed.urllib.request, 'urlopen', denied):
            with self.assertRaises(urllib.error.HTTPError):
                self.seed.find_document('matches/a_b')


if __name__ == "__main__":
    unittest.main()
