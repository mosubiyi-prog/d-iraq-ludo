from pathlib import Path
import sys
import tarfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/app_stability'))
from bind_owned_frame_reader import bind_source
from bind_auth_runtime import body_range,tokens,pairs


class OwnedFrameReadBindingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
            cls.old=archive.extractfile('lib/deda_lab_frame_secure_checkout.dart').read().decode()
        cls.new=bind_source(cls.old)
    def test_only_read_paths_delegate_to_the_new_account_proof(self):
        for method,target in [('isOwned','.isOwned(originalId, frameId)'),('verifiedOwnedFrameIds','.owned(originalId)')]:
            a,b,_,_=body_range(self.new,method)
            self.assertIn('DedaOwnedFrameReader(',self.new[a:b])
            self.assertIn(target,self.new[a:b])
    def test_buy_preflight_price_and_transaction_are_byte_exact(self):
        for method in ['verifiedPurchaseBalance','buyOnce']:
            a,b,_,_=body_range(self.old,method);c,d,_,_=body_range(self.new,method)
            self.assertEqual(self.old[a:b+1],self.new[c:d+1],method)
        a=self.old.index('  static Future<String> _verifyOwner(');b=self.old.index('  static DocumentReference',a)
        c=self.new.index('  static Future<String> _verifyOwner(');d=self.new.index('  static DocumentReference',c)
        self.assertEqual(self.old[a:b],self.new[c:d])
        a=self.old.index('  static bool _valid(');b=self.old.index('  /// Readback',a)
        c=self.new.index('  static bool _valid(');d=self.new.index('  /// Readback',c)
        self.assertEqual(self.old[a:b],self.new[c:d])
        self.assertIn('static const int priceDiamonds = 1000;',self.new)
    def test_read_source_is_balanced_and_double_binding_is_rejected(self):
        pairs(tokens(self.new))
        with self.assertRaises(ValueError):bind_source(self.new)
    def test_transport_has_no_payment_or_session_mutation_calls(self):
        c=(ROOT/'lib/deda_owned_frame_reader.dart').read_text()
        for marker in ['.set(','.update(','.delete(','.signIn','.signOut(','.spend(']:
            self.assertNotIn(marker,c)
        self.assertIn('Source.server',c)
        self.assertIn('DedaOwner18OriginalAccountProof.verify(original)',c)
        self.assertIn('.timeout(deadline)',c)

if __name__=='__main__':unittest.main()
