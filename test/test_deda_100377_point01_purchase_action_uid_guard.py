"""Point01/09: real 13-frame Buy/Use actions must not cross Firebase UID."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SignedFrameUiOwnershipGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui = (ROOT / "lib/deda_lab_frame_purchase_action.dart").read_text()
        cls.checkout = (ROOT / "lib/deda_lab_frame_secure_checkout.dart").read_text()

    def test_uses_original_signed_in_uid_and_fails_closed(self):
        s = self.ui
        self.assertIn('DEDA_100377_POINT01_FRAME_PURCHASE_ACTION_ACCOUNT_UID_GUARD', s)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid", s)
        self.assertIn("Firebase.apps.isEmpty", s)
        self.assertIn("String? _ownedVerifiedUid;", s)
        self.assertIn("_currentUid() == uid", s)
        self.assertIn("_ownedVerifiedUid == _currentUid()", s)
        self.assertIn("onPressed: _busy ? null : _useVerifiedFrame,", s)
        self.assertNotIn("onPressed: _busy ? null : widget.onVerifiedOwned,", s)
        self.assertIn("if (uid == null) return;", s)

    def test_async_receipt_and_purchase_check_same_uid_and_exact_item(self):
        s = self.ui
        self.assertIn("final uid = _currentUid();", s)
        self.assertIn("widget.originalId == owner", s)
        self.assertIn("widget.frameId == frame", s)
        self.assertIn("_sameItem(owner, frame, uid)", s)
        self.assertGreaterEqual(s.count("_sameItem(owner, frame, uid)"), 8)
        self.assertIn("_clearIfAccountChanged(owner, frame, uid);", s)
        self.assertIn("_ownedVerifiedUid = null;", s)
        self.assertIn("_ownedVerifiedUid = uid;", s)
        self.assertIn("widget.onVerifiedOwned();", s)
        self.assertIn("تغيّر الحساب؛ أعد التحقق من ملكية الإطار.", s)

    def test_purchase_owner_must_also_own_canonical_original_id_route(self):
        s = self.checkout
        self.assertIn('DEDA_100377_POINT01_OWNER_UID_ROUTE_PROOF', s)
        self.assertIn("DedaQa32ManagerOriginalOwnerProof.authentic(", s)
        self.assertIn("expectedOriginal: originalId,", s)
        self.assertIn("authUid: uid,", s)
        self.assertIn("account: profile,", s)
        self.assertIn("session: session,", s)
        self.assertIn("route: id,", s)
        self.assertIn("Legacy accounts may lack users.sharePersonalId entirely", s)
        auth = (ROOT / "lib/deda_qa32_manager_original_owner_proof.dart").read_text()
        self.assertIn("route['ownerUid'] != authUid", auth)
        self.assertIn("route['publicId'] != expectedOriginal", auth)
        self.assertIn("accountKey != session['accountKey']", auth)
        self.assertIn("claimedOriginal != expectedOriginal", auth)
        self.assertIn("source: Source.server", s)
        self.assertIn("original-owner-session-not-verified", s)

    def test_original_checkout_is_not_activated_or_changed(self):
        s = self.checkout
        self.assertIn("priceDiamonds = 1000", s)
        self.assertIn("defaultValue: false", s)
        self.assertIn("DedaLabFrameSecureCheckout", s)
        self.assertIn("db.runTransaction<void>", s)
        self.assertIn("account-switched", s)
        self.assertNotIn("defaultValue: true", s)
        ui = self.ui
        self.assertIn("DedaLabFrameSecureCheckout.buyOnce(", ui)
        self.assertIn("DedaLabFrameSecureCheckout.isOwned(", ui)
        self.assertNotIn("DedaDiamondsWallet.spend", ui)
        self.assertIn("الشراء بعد التحقق", ui)


if __name__ == '__main__':
    unittest.main()
