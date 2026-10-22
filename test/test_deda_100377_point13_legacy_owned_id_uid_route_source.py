"""Point13: owner premium identifier Use/list cannot reject genuine legacy accounts.

Guard the ACTUAL Stage71 owned/active service (not a detached hypothetical).
No Firebase writes or switches are enabled; backend policy remains fail-closed.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Stage71OwnedIdentifierAuth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = (ROOT / "lib/deda_stage71_free_owned_use_profile.dart").read_text(
            encoding="utf-8")
        a = src.index("  static Future<String> _requireOriginal(String id) async {")
        b = src.index("  static Future<List<DedaStage71OwnedIdentifier>> owned(", a)
        cls.auth = src[a:b]
        cls.src = src
        cls.proof = (ROOT / "lib/deda_qa32_manager_original_owner_proof.dart").read_text(
            encoding="utf-8")

    def test_reads_three_original_server_records_and_auth_uid(self):
        s = self.auth
        self.assertIn("DEDA_100377_POINT13_LEGACY_ORIGINAL_ID_UID_OWNER_PROOF", s)
        self.assertIn("DedaStage71Admin200.enabled", self.src)
        self.assertIn("if (!enabled || Firebase.apps.isEmpty", s)
        self.assertIn("db.collection('users').doc(uid)", s)
        self.assertIn("db.collection('deda_sessions').doc(uid)", s)
        self.assertIn("db.collection('deda_share_ids').doc(id)", s)
        self.assertEqual(s.count("GetOptions(source: Source.server)"), 3)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != uid", s)

    def test_reuse_shared_owner_proof_not_missing_legacy_share_field(self):
        s = self.auth
        self.assertIn("DedaQa32ManagerOriginalOwnerProof.authentic(", s)
        for check in ("expectedOriginal: id", "authUid: uid",
                      "account: profile", "session: session", "route: route"):
            self.assertIn(check, s)
        self.assertNotIn("profile['sharePersonalId'] != id", s)
        self.assertIn("claimedOriginal != null", self.proof)
        self.assertIn("claimedOriginal != expectedOriginal", self.proof)
        self.assertIn("route['ownerUid'] != authUid", self.proof)
        self.assertIn("route['publicId'] != expectedOriginal", self.proof)
        self.assertIn("accountKey != session['accountKey']", self.proof)

    def test_verified_scope_used_for_list_active_and_use_no_fake_grants(self):
        src = self.src
        self.assertIn("final uid=await _requireOriginal(originalId);", src)
        self.assertGreaterEqual(src.count("_requireOriginal(originalId)"), 4)
        self.assertIn("DedaStage74IdGiftService.isReceived(", src)
        self.assertIn("GetOptions(source: Source.server)", src)
        self.assertIn("DedaStage71OwnedIdentifier.read(", src)
        self.assertIn("if (persisted!=identifier)", src)
        self.assertIn("if (DedaQa32SparkPublicIdentifierDirectory.enabled)", src)
        self.assertIn("defaultValue: false", (ROOT /
            "lib/deda_stage71_free_manager_200_service.dart").read_text())
        self.assertNotIn("DedaDiamondsWallet.spend", src)
        self.assertNotIn("FieldValue.increment", src)


if __name__ == "__main__":
    unittest.main()
