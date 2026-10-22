"""Point08/13: receiving a gifted 200 ID uses the SAME authenticated original owner.

Legacy legitimate accounts with a missing users.sharePersonalId remain
eligible only when their signed-in UID owns the canonical routing record.
No fabricated gift receipt, manager grants or diamonds.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class RecipientIdentityContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source=(ROOT/"lib/deda_stage74_id_gift_service.dart").read_text(encoding="utf-8")
        begin=source.index("  static Future<String> _verifiedOwner(String originalId) async {")
        stop=source.index("  static Future<List<DedaStage74IdGift>> load(",begin)
        cls.identity=source[begin:stop]
        cls.full=source

    def test_owner_proof_read_only_server_data_and_exact_uid_route(self):
        s=self.identity
        self.assertIn("DEDA_100377_POINT08_LEGACY_GIFT_RECIPIENT_UID_ORIGINAL_ROUTE_PROOF",s)
        for collection in ("users","deda_sessions","deda_share_ids"):
            self.assertIn("db.collection('"+collection+"')",s)
        self.assertEqual(s.count("GetOptions(source: Source.server)"),3)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != uid",s)
        self.assertIn("DedaQa32ManagerOriginalOwnerProof.authentic(",s)
        for item in ("expectedOriginal: originalId","authUid: uid",
                     "account: account","session: session","route: route"):
            self.assertIn(item,s)
        self.assertNotIn("account['sharePersonalId'] != originalId",s)
        policy=(ROOT/"lib/deda_qa32_manager_original_owner_proof.dart").read_text(encoding="utf-8")
        self.assertIn("route['ownerUid'] != authUid",policy)
        self.assertIn("claimedOriginal != null",policy)
        self.assertIn("claimedOriginal != expectedOriginal",policy)

    def test_all_receipt_acceptance_paths_use_authenticated_owner(self):
        s=self.full
        self.assertIn("final uid = await _verifiedOwner(originalId);",s)
        self.assertIn("final uid = await _verifiedOwner(gift.originalId);",s)
        self.assertIn("final rows = await load(originalId);",s)
        self.assertIn("DedaStage71Admin200.enabled",s)
        self.assertIn("if (gift.received) return;",s)
        self.assertIn("transaction.set(receipt,",s)
        self.assertIn("row['recipientOriginalId'] != gift.originalId",s)
        self.assertIn("data['receivedAt'] is! Timestamp",s)
        self.assertIn("GetOptions(source: Source.server)",s)
        self.assertNotIn("DedaDiamondsWallet.spend",s)
        self.assertNotIn("FieldValue.increment",s)


if __name__=="__main__":
    unittest.main()
