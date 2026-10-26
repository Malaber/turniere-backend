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
        return {'CFBundleIdentifier': 're.turnie.beta' if beta else 're.turnie',
                'TurniereEnvironment': 'beta' if beta else 'production',
                'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIconBeta' if beta else 'AppIcon'}}}

    def test_beta_export_is_internal_only(self):
        options = plistlib.loads((ROOT / 'ExportOptions.BetaTestFlight.plist').read_bytes())
        guard.validate(self.info(), options, 'beta')

    def test_beta_cannot_use_production_export(self):
        options = plistlib.loads((ROOT / 'ExportOptions.TestFlight.plist').read_bytes())
        with self.assertRaises(ValueError):
            guard.validate(self.info(), options, 'beta')

    def test_production_cannot_upload_beta_archive(self):
        with self.assertRaises(ValueError):
            guard.validate(self.info(), {}, 'production')

    def test_beta_cannot_use_production_icon(self):
        info = self.info()
        info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] = 'AppIcon'
        with self.assertRaises(ValueError):
            guard.validate(info, {'testFlightInternalTestingOnly': True}, 'beta')

    def test_production_export_allowed(self):
        guard.validate(self.info(False), {}, 'production')
