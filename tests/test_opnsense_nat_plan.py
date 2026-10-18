"""Offline tests for read-only NAT plan using observed API response shapes."""
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("opnsense_nat_plan", ROOT / "scripts" / "opnsense-nat-plan.py")
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture(manifest):
    """Minimal synthetic responses matching the actual fields for DNAT/SNAT."""
    expected = module.expected_rules(manifest)
    return {
        "DNAT": {"rows": [dict(fields, uuid=f"test-dnat-{i}")
                          for i, (_, fields) in enumerate(expected["DNAT"])]},
        "SNAT": {"rows": [dict(fields, uuid=f"test-snat-{i}")
                          for i, (_, fields) in enumerate(expected["SNAT"])]},
    }


class NatPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = yaml.safe_load((ROOT / "network/voice-pe.yml").read_text())
        # Supports the one-time description correction already applied in dev01.
        assert cls.manifest["nat"]["destination"][0]["description"] == "TEMP - HA via Nokia WiFi"

    def test_no_change_for_identical_live_state(self):
        states = module.assess(self.manifest, fixture(self.manifest))
        self.assertEqual([v["status"] for v in states], ["NO_CHANGE"] * 4)

    def test_snat_case_and_ip_normalization(self):
        live = fixture(self.manifest)
        snat = live["SNAT"]["rows"][0]
        snat["protocol"] = "TCP"
        snat["destination_net"] = "192.168.10.50/32"
        self.assertEqual(module.assess(self.manifest, live)[-1]["status"], "NO_CHANGE")

    def test_snat_wrong_target_detected(self):
        live = fixture(self.manifest)
        live["SNAT"]["rows"][0]["target"] = "wanip"
        outcome = module.assess(self.manifest, live)[-1]
        self.assertEqual(outcome["status"], "DRIFT")
        self.assertIn("target", outcome["changes"])

    def test_disabled_rule_detected(self):
        live = fixture(self.manifest)
        live["DNAT"]["rows"][1]["disabled"] = "1"
        self.assertEqual(module.assess(self.manifest, live)[1]["status"], "DRIFT")

    def test_missing_rule_not_autocreated(self):
        live = fixture(self.manifest)
        live["DNAT"]["rows"].pop()
        self.assertEqual(module.assess(self.manifest, live)[2]["status"], "MISSING")

    def test_duplicate_description_is_ambiguous(self):
        live = fixture(self.manifest)
        live["DNAT"]["rows"].append(copy.deepcopy(live["DNAT"]["rows"][0]))
        self.assertEqual(module.assess(self.manifest, live)[0]["status"], "AMBIGUOUS")

    def test_missing_rows_rejected(self):
        live = fixture(self.manifest)
        live["SNAT"] = {"status": "error"}
        with self.assertRaises(module.PlanError):
            module.assess(self.manifest, live)

    def test_dnat_source_mismatch_is_drift(self):
        live = fixture(self.manifest)
        live["DNAT"]["rows"][0]["source.network"] = "0.0.0.0/0"
        self.assertEqual(module.assess(self.manifest, live)[0]["status"], "DRIFT")


if __name__ == "__main__":
    unittest.main()
