import importlib.util
import unittest
from pathlib import Path

PATH=Path("tools/deda_owner19_stage62_live_wallet_rules_audit_READONLY_NO_DEPLOY.py")
spec=importlib.util.spec_from_file_location("stage62",PATH)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class LiveWalletReadOnlyComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=Path("firestore.rules").read_text(encoding="utf8")
        cls.candidate=m.candidate(cls.original)

    def test_self_comparison_exposes_risky_unsigned_client_wallet_paths(self):
        r=m.report_policy(self.original,self.original)
        self.assertTrue(r["live_matches_current_repo"])
        self.assertFalse(r["live_matches_stage52_candidate"])
        self.assertTrue(r["live_rules_expected_wallet_sections"])
        self.assertTrue(r["live_client_can_selfmint_gm_test_wallet"])
        self.assertTrue(r["live_client_can_debit_gm_wallet"])
        self.assertTrue(r["live_client_can_debit_gift_balance_without_receipt"])
        self.assertTrue(r["live_genuine_pending_gift_claim_clause"])
        self.assertFalse(r["live_premium_sales_ready"])

    def test_candidate_is_distinct_and_blocks_client_mint_and_spend(self):
        r=m.report_policy(self.original,self.candidate)
        self.assertFalse(r["live_matches_current_repo"])
        self.assertTrue(r["live_matches_stage52_candidate"])
        self.assertFalse(r["live_client_can_selfmint_gm_test_wallet"])
        self.assertFalse(r["live_client_can_debit_gm_wallet"])
        self.assertFalse(r["live_client_can_debit_gift_balance_without_receipt"])
        self.assertTrue(r["live_genuine_pending_gift_claim_clause"])
        self.assertFalse(r["live_premium_sales_ready"])

    def test_unknown_live_policy_is_not_misclassified_safe(self):
        r=m.report_policy(self.original, "rules_version = '2';")
        self.assertFalse(r["live_rules_expected_wallet_sections"])
        self.assertTrue(r["live_wallet_permissions_unknown"])
        self.assertFalse(r["live_premium_sales_ready"])

    def test_whitespace_only_variance_not_reported_as_change(self):
        r=m.report_policy(self.original,self.original.rstrip()+"  \n")
        self.assertTrue(r["live_matches_current_repo"])

    def test_no_wallet_contents_or_keys_in_report(self):
        r=m.report_policy(self.original,self.original)
        self.assertEqual(set(r),set(m.report_policy(self.original,self.original)))
        self.assertFalse(any(isinstance(x,list) or isinstance(x,dict)
                             for x in r.values()))
        self.assertNotIn("accountKey",str(r))
        self.assertNotIn("userUid",str(r))

if __name__=="__main__":
    unittest.main()
