import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

FILE = Path("tools/deda_owner19_stage52_wallet_rules_candidate_OFFLINE_NO_DEPLOY.py")
spec = importlib.util.spec_from_file_location("deda_owner19_stage52", FILE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class TestStage52WalletRulesCandidate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules = Path("firestore.rules").read_text(encoding="utf8")

    def test_detect_old_unsigned_client_wallet_debits(self):
        info = m.inspect(self.rules)
        self.assertTrue(info["client_manager_test_million_create_permitted"])
        self.assertTrue(info["client_manager_wallet_debit_permitted"])
        self.assertTrue(info["client_gift_wallet_unreceipted_debit_permitted"])
        self.assertTrue(info["gift_claim_branch_preserved"])
        self.assertFalse(info["ready_to_deploy"])

    def test_candidate_prevents_client_debit_without_loss_of_real_gift_claim(self):
        result = m.candidate(self.rules)
        state = m.inspect(result)
        self.assertFalse(state["client_manager_test_million_create_permitted"])
        self.assertFalse(state["client_manager_wallet_debit_permitted"])
        self.assertFalse(state["client_gift_wallet_unreceipted_debit_permitted"])
        self.assertTrue(state["gift_claim_branch_preserved"])
        self.assertFalse(state["ready_to_deploy"])
        self.assertIn("allow create, update: if false;", result)
        self.assertIn(
            "validGiftClaim(request.resource.data.lastClaimGiftId, publicId)",
            result,
        )
        self.assertIn("allow create: if verifiedDiamondsPersonalOwner(publicId)",
                      result)
        self.assertIn("allow get: if isGeneralManagerPersonalAccount(accountKey);",
                      result)
        self.assertEqual(self.rules.count("match /deda_diamond_gifts/{giftId}"),
                         result.count("match /deda_diamond_gifts/{giftId}"))
        self.assertEqual(self.rules.count("match /deda_share_ids/"),
                         result.count("match /deda_share_ids/"))
        self.assertEqual(self.rules.count("match /deda_admin_diamond_wallets/"),
                         result.count("match /deda_admin_diamond_wallets/"))
        self.assertIn("DEDA_OWNER19_STAGE52", "DEDA_OWNER19_STAGE52")

    def test_exactly_two_wallet_policy_sections_can_change(self):
        original = self.rules
        updated = m.candidate(original)
        a, b, old_gm = m._slice(original, m.GM_START, m.GM_END)
        _, _, new_gm = m._slice(updated, m.GM_START, m.GM_END)
        c, d, old_gift = m._slice(original, m.GIFT_START, m.GIFT_END)
        _, _, new_gift = m._slice(updated, m.GIFT_START, m.GIFT_END)
        self.assertEqual(updated.replace(new_gm, old_gm, 1).replace(
            new_gift, old_gift, 1), original)
        self.assertTrue(a < b < c < d)

    def test_changed_source_or_second_activation_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            m.candidate(self.rules.replace(
                m.GIFT_CLIENT_DECREASE, "allow update: if true;", 1))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            m.candidate(self.rules.replace(
                m.GM_CREATE, "allow create: if false", 1))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            m.candidate(m.candidate(self.rules))

    def test_cli_only_produces_isolated_temp_file(self):
        with tempfile.TemporaryDirectory() as temp:
            rules_path = Path(temp) / "original.rules"
            rules_path.write_text(self.rules, encoding="utf8")
            proposed = Path(temp) / "stage52-candidate.rules"
            run = subprocess.run(
                [sys.executable, str(FILE), str(rules_path), str(proposed)],
                capture_output=True, text=True,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(rules_path.read_text(encoding="utf8"), self.rules)
            self.assertEqual(proposed.read_text(encoding="utf8"),
                             m.candidate(self.rules))
            self.assertIn("NO DEPLOY", run.stdout)

    def test_reject_writing_to_real_firestore_rules_path(self):
        command = [sys.executable, str(FILE), "firestore.rules",
                   "firestore.rules"]
        run = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("SAFE_STOP", run.stderr + run.stdout)


if __name__ == "__main__":
    unittest.main()
