import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image
from capture_screenshots import SCENES, package_device


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.attachments = []
        for scene in SCENES:
            filename = f"{scene}.png"
            Image.new("RGBA", (12, 26), (0, 100, 200, 255)).save(self.root / filename)
            self.attachments.append({"suggestedHumanReadableName": f"{scene}_0.png",
                                     "exportedFileName": filename,
                                     "isAssociatedWithFailure": False})

    def package(self):
        (self.root / "manifest.json").write_text(json.dumps([{"attachments": self.attachments}]))
        return package_device(self.root, self.root / "output", (12, 26))

    def test_localized_opaque_images(self):
        manifest = self.package()
        self.assertEqual(len(manifest), 4)
        for entry in manifest:
            with Image.open(self.root / "output" / entry["file"]) as image:
                self.assertEqual(image.mode, "RGB")
                self.assertEqual(image.size, (12, 26))
            self.assertEqual(len(entry["sha256"]), 64)

    def test_missing_scene_rejected(self):
        self.attachments.pop()
        with self.assertRaisesRegex(ValueError, "Missing screenshots"):
            self.package()

    def test_duplicate_scene_rejected(self):
        self.attachments.append(self.attachments[0])
        with self.assertRaisesRegex(ValueError, "Duplicate or failed"):
            self.package()

    def test_failed_capture_rejected(self):
        self.attachments[0]["isAssociatedWithFailure"] = True
        with self.assertRaisesRegex(ValueError, "Duplicate or failed"):
            self.package()

    def test_wrong_dimensions_rejected(self):
        Image.new("RGB", (13, 26)).save(self.root / self.attachments[0]["exportedFileName"])
        with self.assertRaisesRegex(ValueError, "expected"):
            self.package()


if __name__ == "__main__":
    unittest.main()
