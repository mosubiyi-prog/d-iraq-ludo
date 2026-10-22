"""Point01 production launch compatibility gate; read repository code only.

The original DEDA badge/frame shop uses the ordinary DedaDiamondsWallet
(purchases spend local earned balance first, with a remote gifted remainder).
The new 13-LAB-frame checkout currently spends ONLY verified remote gifts.
The proposed policy also stops legacy unreceipted gifted-balance deductions.
These differences MUST NOT be concealed by passing synthetic checkout tests.

This is a non-deploying source audit. It intentionally returns NO-GO until
a tested, same-account, same-spendable-wallet bridge and receipt path exist.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TestPoint01ExistingShopCompatibility(unittest.TestCase):
    def test_existing_shop_really_uses_existing_diamonds_wallet(self):
        old_store = (ROOT / "tools/style_badges_frames_100273_2026_10_05.py").read_text()
        wallet_patch = (ROOT / "tools/social_ui_wallet_fixes_100270_2026_10_04.py").read_text()
        self.assertIn("return DedaDiamondsWallet.spend(price);", old_store)
        self.assertIn("final localToSpend = amount <= current.balance", wallet_patch)
        self.assertIn("final giftedToSpend = amount - localToSpend;", wallet_patch)
        self.assertIn("DedaBackend.spendPersonalGiftedDiamonds(", wallet_patch)

    def test_new_checkout_is_remote_gifts_only_not_the_existing_shop_balance(self):
        new_checkout = (ROOT / "lib/deda_lab_frame_secure_checkout.dart").read_text()
        new_ui = (ROOT / "lib/deda_lab_frame_purchase_action.dart").read_text()
        self.assertIn("collection('deda_diamond_gift_balances')", new_checkout)
        self.assertIn("amount - priceDiamonds", new_checkout)
        self.assertNotIn("DedaDiamondsWallet.spend", new_checkout)
        self.assertIn("'الشراء بعد التحقق'", new_ui)
        self.assertIn("defaultValue: false", new_checkout)
        self.assertEqual(len(re.findall(r"'FRAME_(?:0[3-9]|1[0-6])'", new_checkout)), 14)

    def test_proposed_live_policy_changes_old_gift_spending_permission(self):
        rules = (ROOT / "tools/deda_stage69_merge_5000_checkout_into_live_rules_READONLY_NO_DEPLOY.py").read_text()
        self.assertIn("wallet.replace(GIFT_CLIENT_DECREASE,'',1)", rules)
        self.assertIn("SAFE_STOP_UNRECEIPTED_DEBIT_REMAINS", rules)

    def test_never_enable_live_with_unreconciled_spendable_wallet(self):
        # Fail-closed guard on production enablement, not a declaration of
        # readiness. Synthetic emulator PASS alone can never waive this.
        checkout = (ROOT / "lib/deda_lab_frame_secure_checkout.dart").read_text()
        self.assertIn("defaultValue: false", checkout)
        self.assertNotIn("defaultValue: true", checkout)
        print(
            "POINT01_PRODUCTION_NO_GO: Original store spends local earned "
            "and remote gifted diamonds; new LAB checkout spends remote gifts "
            "only. Publishing proposed wallet hardening could reject existing "
            "gift-funded badge/frame purchases. Reconcile first. NO DEPLOY."
        )


if __name__ == "__main__":
    unittest.main()
