#!/usr/bin/env python3
"""Point09: original-ID-owned items must never bleed between logged-in accounts.

Source-only checks; cloud wallet/XP recovery is deliberately not represented
as completed. This regression file does not patch or deploy any backend.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "lib/deda_stage71_free_owned_use_profile.dart").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "functions/deda_qa32_account_continuity_policy_NOT_EXPORTED.js").read_text(
    encoding="utf-8"
)


def scope(begin, end):
    return SOURCE[SOURCE.index(begin):SOURCE.index(end, SOURCE.index(begin))]


class Point09IdentityContinuity(unittest.TestCase):
    def test_owned_ids_reset_previous_account_immediately(self):
        part = scope("class _DedaStage71OwnedIdsPanelState", "/// On the user's personal hero")
        self.assertIn("DEDA_100377_POINT09_OWNED_IDS_ACCOUNT_SWITCH_NO_STALE_ROWS", part)
        start = part.index("if (oldWidget.originalId != widget.originalId)")
        stop = part.index("Future<void> _load()", start)
        swapped = part[start:stop]
        for required in ("++_generation;", "_ids = null;", "_active = null;",
                         "_busy = false;", "_load();"):
            self.assertIn(required, swapped)
        self.assertLess(swapped.index("_ids = null;"), swapped.index("_load();"))
        self.assertIn("final generation = ++_generation;", part)
        self.assertGreaterEqual(part.count("generation != _generation"), 3)
        self.assertIn("widget.originalId != original", part)
        self.assertIn("DedaStage71ActiveIdRefresh.notifier.removeListener(_onActiveChanged)", part)

    def test_old_account_use_reply_cannot_mark_new_account_active(self):
        part = scope("class _DedaStage71OwnedIdsPanelState", "/// On the user's personal hero")
        start = part.index("Future<void> _use(String id) async")
        stop = part.index("@override\n  Widget build(", start)
        use = part[start:stop]
        self.assertIn("final original = widget.originalId;", use)
        self.assertIn("await DedaStage71OwnedIdentifierService.use(original, id);", use)
        self.assertIn("generation != _generation", use)
        self.assertIn("widget.originalId != original", use)
        self.assertIn("setState(() => _active = id);", use)
        self.assertNotIn("DedaStage71OwnedIdentifierService.use(widget.originalId,id)", use)

    def test_foil_falls_back_until_active_id_belongs_to_visible_original(self):
        part = SOURCE[SOURCE.index("class _DedaStage71ActiveProfileFoilState"):]
        self.assertIn("DEDA_100377_POINT09_ACTIVE_FOIL_ACCOUNT_SWITCH_SAFE_FALLBACK", part)
        self.assertIn("_verifiedOriginal = null;", part)
        self.assertIn("_verifiedOriginal = original;", part)
        self.assertIn("_verifiedOriginal != widget.originalId", part)
        self.assertGreaterEqual(part.count("generation != _generation"), 4)
        self.assertIn("DedaStage71ActiveIdRefresh.notifier.removeListener(_load)", part)
        self.assertIn("DedaStage71OwnedIdentifierService.active(original)", part)
        self.assertIn("DedaStage71OwnedIdentifierService.owned(original)", part)

    def test_cross_device_money_and_xp_never_restored_from_unverified_local_max(self):
        self.assertIn("function inspectContinuity(proof, server, device)", SERVER)
        self.assertIn('status: "needs-verified-recovery"', SERVER)
        self.assertIn('status: "display-verified-server"', SERVER)
        self.assertIn("allowWrite: false", SERVER)
        self.assertNotIn("Math.max", SERVER)
        self.assertNotIn("firebase-admin", SERVER)
        service = scope("class DedaStage71OwnedIdentifierService", "/// User's Edit Profile:")
        self.assertIn("deda_stage71_active_identifier", service)
        self.assertIn("DedaStage74IdGiftService.isReceived", service)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid!=uid", service)
        self.assertNotIn("DedaDiamondsWallet", service)


if __name__ == "__main__":
    unittest.main()
