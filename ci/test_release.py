import unittest
from release import next_tag


class ReleaseVersionTests(unittest.TestCase):
    def test_first_release_ignores_non_release_tags(self):
        self.assertEqual(next_tag(['ios-0.2', 'v1.2', 'test'], []), 'v0.0.1')

    def test_patch_uses_numeric_order(self):
        self.assertEqual(next_tag(['v0.9.9', 'v0.10.2', 'v0.10.1'], []), 'v0.10.3')

    def test_retry_reuses_commit_release(self):
        self.assertEqual(next_tag(['v0.10.2', 'v0.10.3'], ['v0.10.2']), 'v0.10.2')


class ReleaseSafetyTests(unittest.TestCase):
    def test_missing_test_image_prevents_promotion(self):
        import os
        from unittest.mock import patch
        import release
        calls = []
        def command(*args):
            calls.append(args)
            if args == ('git', 'rev-parse', 'HEAD'):
                return 'a' * 40
            if args[0] == 'git':
                return ''
            if 'inspect' in args and 'backend-test:' in args[-1]:
                raise RuntimeError('test image missing')
            return ''
        with patch.dict(os.environ, GITHUB_REPOSITORY='Malaber/turniere-backend', GITHUB_SHA='a' * 40), patch('release.run', side_effect=command):
            with self.assertRaisesRegex(RuntimeError, 'test image missing'):
                release.main()
        self.assertFalse(any('create' in args or 'push' in args for args in calls))

    def test_old_release_does_not_move_latest(self):
        import os
        from unittest.mock import patch
        import release
        with patch.dict(os.environ, GITHUB_REPOSITORY='Malaber/turniere-backend', GITHUB_SHA='a' * 40), patch('release.run', side_effect=['a' * 40, 'v0.0.1\nv0.0.2', 'v0.0.1']) as command:
            release.main()
        self.assertEqual(command.call_count, 3)
