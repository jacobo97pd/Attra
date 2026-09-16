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
            fields = {"isBot": {"booleanValue": True},
                      "photoUrl": {"stringValue": "https://example.test/photo"},
                      "displayName": {"stringValue": "Demo"}}
            return io.BytesIO(json.dumps({"fields": fields}).encode())

        with patch.object(self.seed.urllib.request, "urlopen", fake_urlopen):
            self.run_seed()
        methods = [request.get_method() for request in requests]
        self.assertEqual(methods[:9], ["GET"] * 9)
        self.assertEqual(methods[9:], ["POST"])

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
        }), patch.object(self.seed.urllib.request, 'urlopen') as network:
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
                patch.object(self.seed.urllib.request, 'urlopen') as network:
            with self.assertRaisesRegex(SystemExit, 'Falta cuenta'):
                self.run_seed('--peer-uid', 'other_review_account')
        network.assert_not_called()
        self.assertFalse(self.seed.PENDING_WRITES)


if __name__ == "__main__":
    unittest.main()
