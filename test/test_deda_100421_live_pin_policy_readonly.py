"""Local policy contract fixtures: no Firebase/network access or real PIN."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILE = ROOT / "tools/deda_100421_pin_live_rules_readonly_no_deploy.py"
spec = importlib.util.spec_from_file_location("deda_100421_policy", FILE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class PinPolicyAuditContract(unittest.TestCase):
    def test_exact_repository_policy_is_detected_without_logging_secrets(self):
        text = (ROOT / "firestore.rules").read_text(encoding="utf8")
        report = mod.policy_flags(text)
        self.assertTrue(report["pin_proof_rule_found"])
        self.assertTrue(report["pin_proof_uid_scoped"])
        self.assertTrue(report["pin_matches_server_credential"])
        self.assertTrue(report["pin_proof_document_contains_pin"])
        self.assertTrue(report["pin_opens_session_rule_found"])
        self.assertTrue(report["session_verified_against_pin_attempt"])
        self.assertTrue(report["trusted_install_can_open_session_without_pin_proof"])
        self.assertTrue(report["account_profile_trusted_install_client_editable"])
        self.assertFalse(report["session_requires_canonical_original_id"])
        self.assertFalse(report["explicit_attempt_count_or_lockout_in_pin_rule"])
        self.assertFalse(report["recovery_sufficient_for_finances"])

    def test_missing_rules_fail_to_unproven_not_secure(self):
        report = mod.policy_flags("rules_version = '2';")
        self.assertFalse(report["pin_proof_rule_found"])
        self.assertFalse(report["pin_opens_session_rule_found"])
        self.assertFalse(report["recovery_sufficient_for_finances"])

    def test_rule_match_uniqueness_required(self):
        text = (ROOT / "firestore.rules").read_text(encoding="utf8")
        anchor = "match /deda_auth_attempts/{uid} {"
        report = mod.policy_flags(text + "\n" + anchor)
        self.assertFalse(report["pin_proof_rule_found"])


if __name__ == "__main__":
    unittest.main()
