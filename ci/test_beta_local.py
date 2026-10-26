import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('beta_lab', Path(__file__).resolve().parents[1] / 'lib/beta_lab/cli.py')
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class BetaLabTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name)
        for key, value in [('ENV', self.state / 'compose.env'), ('PAIR', self.state / 'pair.json')]:
            mock = patch.object(lab, key, value)
            mock.start()
            self.addCleanup(mock.stop)
        lab.initialize()

    def test_init_preserves_credentials_and_private_permissions(self):
        before = lab.ENV.read_text()
        lab.initialize()
        self.assertEqual(lab.ENV.read_text(), before)
        self.assertEqual(lab.ENV.stat().st_mode & 0o777, 0o600)

    def test_pair_reuses_follower_and_only_writes_expected_targets(self):
        calls = []

        class FakeAPI:
            def __init__(self, base):
                self.base = base

            def login(self, email, password):
                pass

            def call(self, method, path, body=None):
                calls.append((self.base, method, path, body))
                if method == 'GET':
                    return {'id': 7, 'name': 'Local tournament', 'read_only_mode': False}
                if self.base == lab.BETA_API:
                    return {'id': 42}
                return {}

        with patch.object(lab, 'API', FakeAPI), patch('builtins.input', return_value='owner@example.test'), \
                patch.object(lab.getpass, 'getpass', return_value='secret'):
            lab.pair(7)
            lab.pair(7)
            with self.assertRaises(SystemExit):
                lab.pair(8)
        remote_writes = [call for call in calls if call[0] == lab.BETA_API]
        self.assertEqual(len(remote_writes), 1)
        self.assertTrue(remote_writes[0][3]['read_only_mode'])
        self.assertFalse(remote_writes[0][3]['public'])
        saved = json.loads(lab.PAIR.read_text())
        self.assertEqual(saved['follower_id'], 42)
        self.assertEqual(lab.PAIR.stat().st_mode & 0o777, 0o600)
        writes = [call for call in calls if call[1] == 'PATCH']
        self.assertEqual(len(writes), 2)
        self.assertEqual(writes[0][3]['sync_auth_token'], saved['sync_token'])
        self.assertEqual(writes[0][3]['sync_target_url'], 'https://beta.api.turnie.re/tournaments/42/sync_state')

    def test_down_preserves_volume(self):
        with patch.object(lab, 'compose') as compose, patch('sys.argv', ['cli.py', 'down']):
            lab.main()
        compose.assert_called_once_with('down')


if __name__ == '__main__':
    unittest.main()
