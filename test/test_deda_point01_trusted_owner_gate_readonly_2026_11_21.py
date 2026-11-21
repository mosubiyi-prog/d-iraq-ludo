"""Point 01 safe-HOLD tests: never grant access on mere historical document presence."""
from __future__ import annotations
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILE = ROOT / "tools/deda_point01_trusted_owner_gate_readonly_2026_11_21.py"
spec = importlib.util.spec_from_file_location("point01_readonly", FILE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ReadOnlyOwnerGateTest(unittest.TestCase):
    def test_any_state_stays_held_without_external_attestation(self):
        for history in [False, True]:
            for auth in [False, True]:
                for durable in [False, True]:
                    for sessions in [False, True]:
                        for record in [False, True]:
                            decision = mod.assess(history, auth, durable, sessions, record)
                            self.assertTrue(decision.startswith("HOLD_"))
    def test_no_email_or_provider_means_no_login(self):
        self.assertEqual(
            mod.assess(True, True, False, False, False),
            "HOLD_NO_HISTORICAL_DURABLE_AUTH_PROVIDER",
        )
    def test_provider_alone_cannot_claim_ownership(self):
        self.assertEqual(
            mod.assess(True, True, True, True, True),
            "HOLD_INDEPENDENT_OWNERSHIP_ATTESTATION_NOT_VERIFIED",
        )
    def test_uid_history_mismatch_has_priority(self):
        self.assertEqual(
            mod.assess(False, True, True, True, True),
            "HOLD_AUTHORITATIVE_HISTORY_CONFLICT",
        )
    def test_no_firebase_access_at_module_import(self):
        src = FILE.read_text(encoding="utf-8")
        for forbidden in ("sign_in_with", "signInAnonymously", ".set(", ".update(",
                          ".delete(", ".create(", ".add(", "create_custom_token",
                          "update_user(", "delete_user(", "create_user(",
                          "revoke_refresh_tokens(", "print(account", "print(uid",
                          "print(original_id", "print(info"):
            self.assertNotIn(forbidden, src)
    def test_id_is_only_from_approved_source(self):
        self.assertRegex(mod.approved_original_id(), mod.ORIGINAL_RE)

if __name__ == "__main__":
    unittest.main()
