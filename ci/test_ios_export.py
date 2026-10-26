import importlib.util
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'ios/TurniereIOS'
spec = importlib.util.spec_from_file_location('export_guard', ROOT / 'Scripts/validate_testflight_export.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ExportTests(unittest.TestCase):
    def info(self, beta=True):
        return {'CFBundleIdentifier': 're.turnie',
                'TurniereEnvironment': 'beta' if beta else 'production',
                'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIconBeta' if beta else 'AppIcon'}}}

    def test_beta_uses_shared_export_for_external_testers(self):
        options = plistlib.loads((ROOT / 'ExportOptions.TestFlight.plist').read_bytes())
        guard.validate(self.info(), options, 'beta')

    def test_internal_only_export_rejected(self):
        with self.assertRaises(ValueError):
            guard.validate(self.info(), {'testFlightInternalTestingOnly': True}, 'beta')

    def test_production_cannot_upload_beta_archive(self):
        with self.assertRaises(ValueError):
            guard.validate(self.info(), {}, 'production')

    def test_beta_cannot_use_production_icon(self):
        info = self.info()
        info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] = 'AppIcon'
        with self.assertRaises(ValueError):
            guard.validate(info, {}, 'beta')

    def test_production_export_allowed(self):
        guard.validate(self.info(False), {}, 'production')


class PairedUploadTests(unittest.TestCase):
    def test_pair_uses_distinct_builds(self):
        from unittest.mock import patch, call
        import tasks
        with patch('tasks.upload_ios_testflight') as upload:
            tasks.upload_ios_testflight_pair.body(None, version='0.2', build_number='6')
            self.assertEqual(upload.call_args_list, [
                call(None, version='0.2', build_number='6'),
                call(None, version='0.2', build_number='7', beta=True)])

    def test_pair_requires_explicit_build(self):
        from unittest.mock import patch
        import tasks
        with patch('tasks.upload_ios_testflight') as upload:
            with self.assertRaises(ValueError):
                tasks.upload_ios_testflight_pair.body(None)
            upload.assert_not_called()

    def test_failed_production_stops_pair(self):
        from unittest.mock import patch
        import tasks
        with patch('tasks.upload_ios_testflight', side_effect=RuntimeError('upload failed')) as upload:
            with self.assertRaises(RuntimeError):
                tasks.upload_ios_testflight_pair.body(None, build_number='6')
            self.assertEqual(upload.call_count, 1)
