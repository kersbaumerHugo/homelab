"""Offline checks of the temporary voice PE network model."""
import copy
import importlib.util
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("verify_voice_pe", ROOT / "scripts" / "verify-voice-pe.py")
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class VoicePEManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = yaml.safe_load((ROOT / "network" / "voice-pe.yml").read_text())

    def test_manifest_valid(self):
        module.validate(self.original)

    def test_deny_any_wan_source(self):
        changed = copy.deepcopy(self.original)
        changed["nat"]["destination"][1]["source"] = "0.0.0.0/0"
        with self.assertRaisesRegex(ValueError, "Unsafe interface/source"):
            module.validate(changed)

    def test_deny_redirect_to_wrong_service(self):
        changed = copy.deepcopy(self.original)
        changed["nat"]["destination"][0]["target_port"] = 22
        with self.assertRaisesRegex(ValueError, "Unexpected forwarding"):
            module.validate(changed)

    def test_deny_wrong_hairpin_translation(self):
        changed = copy.deepcopy(self.original)
        changed["nat"]["source"][0]["translation"] = "192.168.1.79"
        with self.assertRaisesRegex(ValueError, "Unexpected source NAT"):
            module.validate(changed)

    def test_deny_wrong_advertised_url(self):
        changed = copy.deepcopy(self.original)
        changed["home_assistant"]["advertised_url"] = "http://192.168.10.50"
        with self.assertRaisesRegex(ValueError, "advertised_url"):
            module.validate(changed)


if __name__ == "__main__":
    unittest.main()
