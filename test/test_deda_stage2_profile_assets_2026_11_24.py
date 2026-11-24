"""DEDA Stage2 source-only profile parity and UID rotation regression.

Checks existing authoritative sources; does NOT grant gifts, buy frames,
activate premium IDs, change balances, or access production Firebase.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / "lib" / name).read_text(encoding="utf-8")


class Stage2ProfileAssetsSourceParity(unittest.TestCase):
    def test_original_free_frame_catalog_stays_separate_from_paid_ownership(self):
        free = source("deda_100377_profile_free_inventory.dart")
        paid = source("deda_owned_frame_reader.dart")
        for marker in ("frameChoices = <int>[0, 1, 2, 3, 4, 5]",
                       "DedaMyStoreProof.basicFree", "DedaMyStoreProof.deviceSaved"):
            self.assertIn(marker, free)
        for marker in ("DedaOwner18OriginalAccountProof.verify(original)",
                       "GetOptions(source:Source.server)",
                       "account-changed-during-frame-inventory",
                       "frame-server-proof-required",
                       "partial-or-forged-frame-ownership"):
            self.assertIn(marker, paid)
        self.assertNotIn("DedaDiamondsWallet.spend(", paid)
        self.assertNotIn("FieldValue.increment(", paid)

    def test_original_and_premium_ids_keep_server_ownership_and_gift_receipts(self):
        ids = source("deda_stage71_free_owned_use_profile.dart")
        store = source("deda_100377_my_store_page_staged.dart")
        for marker in ("DedaQa32ManagerOriginalOwnerProof.authentic(",
                       "acceptedOwnedForMyStore(",
                       "DedaStage74IdGiftService.receivedNames(originalId)",
                       "account-switched-after-gift-receipts",
                       "account-switched-after-active-gift-receipt",
                       "if (!doc.exists) return originalId;"):
            self.assertIn(marker, ids)
        self.assertIn("deda_p12_canonical_original_id", store)
        self.assertIn("deda_p12_verified_active_display_id", store)
        self.assertEqual(store.count("class DedaMyStorePage extends StatelessWidget"), 1)
        self.assertNotIn("DedaDiamondsWallet.spend(", ids)

    def test_diamonds_display_only_no_wallet_merger_or_admin_gift_balance(self):
        wallet = source("deda_profile_visible_diamonds.dart")
        for marker in ("ordinaryEarnedAndGifted", "hasGeneralManagerPersonalWallet",
                       "generalManagerPersonal", "return ordinary + manager;"):
            self.assertIn(marker, wallet)
        for forbidden in ("FirebaseFirestore", "FieldValue.increment(",
                          "DedaDiamondsWallet.spend(", "runTransaction("):
            self.assertNotIn(forbidden, wallet)
        self.assertIn("The separate administrative gift wallet is NOT part", wallet)

    def test_level_badges_remain_policy_gated_not_minted_from_local_points(self):
        policy = source("deda_100377_level_achievement_badges_policy.dart")
        page = source("deda_100377_level_achievements_page_staged.dart")
        self.assertIn("defaultValue: false", policy)
        self.assertIn("if (!releaseEnabled) return null;", policy)
        self.assertIn("verifiedAccountAndLevel", policy)
        self.assertIn("DedaLevelBadgePolicy.evaluate(", page)
        for forbidden in ("DedaDiamondsWallet.spend(", "FieldValue.increment("):
            self.assertNotIn(forbidden, policy)

    def test_hadaya_identifier_rows_revoke_immediately_after_auth_rotation(self):
        ui = source("deda_stage74_hadaya_identifier_section.dart")
        service = source("deda_stage74_id_gift_service.dart")
        for marker in ("StreamSubscription<User?>? _auth;",
                       "_observedUid = _currentUid();",
                       "authStateChanges().listen(_onAuthChanged)",
                       "if (nextUid == _observedUid) return;",
                       "_auth?.cancel();",
                       "_verifiedUid == _currentUid() ? _gifts : null",
                       "await DedaStage74IdGiftService.receive(gift);"):
            self.assertIn(marker, ui)
        callback = ui[ui.index("void _onAuthChanged(User? user)"):ui.index("void initState()", ui.index("void _onAuthChanged(User? user)"))]
        ordered = ("++_generation;", "setState(() {", "_gifts = null;",
                   "_verifiedUid = null;", "if (nextUid != null) _refresh();")
        offsets = [callback.index(marker) for marker in ordered]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("GetOptions(source: Source.server)", service)
        self.assertIn("transaction.set(receipt,", service)
        for forbidden in ("signInAnonymously(", "DedaDiamondsWallet.spend(",
                          "FieldValue.increment(", "transaction.set("):
            self.assertNotIn(forbidden, ui)

    def test_old_gift_row_and_claim_completion_cannot_revive_after_rotation(self):
        ui = source("deda_stage74_hadaya_identifier_section.dart")
        for begin, end in (
            ("void _onAuthChanged(User? user)", "void initState()"),
            ("void didUpdateWidget(", "void dispose()"),
            ("void dispose()", "Future<void> _refresh()"),
        ):
            part = ui[ui.index(begin):ui.index(end, ui.index(begin))]
            self.assertIn("_claimToken = null;", part)
        receive = ui[ui.index("Future<void> _receive("):ui.index("Widget _giftTile(")]
        self.assertIn("rowGeneration != _generation", receive)
        self.assertIn("identical(_claimToken, token)", receive)
        self.assertIn("_claimToken = token;", receive)
        self.assertIn("if (!claimCurrent()) return;", receive)
        self.assertEqual(receive.count("if (claimCurrent()) {"), 3)
        self.assertLess(receive.index("if (!claimCurrent()) return;"),
                        receive.index("await _refresh();"))
        self.assertNotIn("_claimingId == gift.identifier", receive)
        self.assertIn("final rowGeneration = _generation;", ui)
        self.assertIn("_receive(gift, rowGeneration)", ui)


if __name__ == "__main__":
    unittest.main()
