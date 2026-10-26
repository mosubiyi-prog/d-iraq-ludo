import hashlib
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('native_owned_harness',ROOT/'tools/app_stability/native_ownership/prepare-harness.py')
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)


class OwnedFrameNativeHarnessTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.base=self.root/'base';self.harness=self.root/'app'
        (self.base/'lib').mkdir(parents=True);(self.harness/'lib').mkdir(parents=True)
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as t:
            for name in ['pubspec.lock','lib/deda_backend.dart',*['lib/'+n for n in native.ORIGINAL]]:
                (self.base/name).write_bytes(t.extractfile(name).read())
        app=self.harness/'android/app';(app/'src/main').mkdir(parents=True)
        (app/'src/main/AndroidManifest.xml').write_text('<manifest><application/></manifest>')
        (app/'build.gradle.kts').write_text('applicationId = "dev.deda.qa.deda_owned_qa"')
        (self.harness/'.metadata').write_text('isolated')
    def tearDown(self):self.tmp.cleanup()
    def test_real_sources_are_copied_and_only_read_functions_are_patched(self):
        native.prepare(self.harness,self.base)
        data=json.loads((self.harness/'native-owned-source-manifest.json').read_text())
        for name in native.ORIGINAL:
            expected=(self.base/'lib'/name).read_bytes()
            actual=(self.harness/'lib'/name).read_bytes()
            if name=='deda_lab_frame_secure_checkout.dart':expected=native.bind_source(expected.decode()).encode()
            self.assertEqual(actual,expected)
            self.assertEqual(data['files']['lib/'+name],hashlib.sha256(actual).hexdigest())
        self.assertEqual(data['package'],'dev.deda.qa.deda_owned_qa')
        self.assertTrue(data['purchaseDependenciesAreFailingStubs'])
        self.assertFalse((self.harness/'android/app/google-services.json').exists())
    def test_changed_original_purchase_source_is_rejected(self):
        (self.base/'lib/deda_owner18_frame_checkout.dart').write_text('drift')
        with self.assertRaisesRegex(ValueError,'hash drift'):native.prepare(self.harness,self.base)
        self.assertEqual(list((self.harness/'lib').iterdir()),[])
    def test_gift_reads_are_exact_original_methods_without_any_wallet_mutator(self):
        native.prepare(self.harness,self.base)
        original=(self.base/'lib/deda_backend.dart').read_text()
        output=(self.harness/'lib/deda_backend.dart').read_text()
        methods=native.gift_read_methods(original)
        self.assertIn(methods,output)
        for name in ['personalGiftedDiamondBalance','watchPersonalDiamondGifts','_sortedGiftMaps']:
            self.assertIn(name,methods)
        for forbidden in ['claimDiamondGift','spendPersonalGiftedDiamonds','ensureGeneralManager', '.set(','.update(','.delete(','.runTransaction(']:
            self.assertNotIn(forbidden,output)
        data=json.loads((self.harness/'native-owned-source-manifest.json').read_text())
        self.assertEqual(data['originalGiftReadMethodsSHA256'],hashlib.sha256(methods.encode()).hexdigest())
        self.assertTrue(data['originalGiftReadMethodsByteExact'])
        self.assertFalse(data['earnedBalanceMigrationTested'])
    def test_changed_backend_or_extraction_anchors_are_rejected_before_writes(self):
        original=(self.base/'lib/deda_backend.dart').read_text()
        (self.base/'lib/deda_backend.dart').write_text(original+'\n// drift')
        with self.assertRaisesRegex(ValueError,'backend source hash drift'):native.prepare(self.harness,self.base)
        self.assertEqual(list((self.harness/'lib').iterdir()),[])
        with self.assertRaisesRegex(ValueError,'gift read source drift'):
            native.gift_read_methods(original.replace('personalGiftedDiamondBalance(', 'changed('))
    def test_gift_reads_recover_only_existing_balance_and_never_accept_pending_gift(self):
        main=(ROOT/'tools/app_stability/native_ownership/main.dart').read_text()
        self.assertEqual(main.count('() => verifyGiftReads(original)'),2)
        self.assertIn('DedaBackend.personalGiftedDiamondBalance(original)==42000',main)
        self.assertIn("['native-owned-gift-pending']?['status']=='pending'",main)
        self.assertIn('await reject(()=>DedaBackend.personalGiftedDiamondBalance(original))',main)
        self.assertNotIn('claimDiamondGift(',main)
        server=(ROOT/'tools/app_stability/native_ownership/policy-server.cjs').read_text()
        fingerprint=server[server.index('async function fingerprint'):server.index('function save()')]
        self.assertIn('native-owned-gift-received',fingerprint)
        self.assertIn('native-owned-gift-pending',fingerprint)
    def test_preparation_never_overwrites_existing_harness_or_production_config(self):
        native.prepare(self.harness,self.base)
        with self.assertRaises(ValueError):native.prepare(self.harness,self.base)
        with self.assertRaises(ValueError):native.prepare(ROOT,self.base)
    def test_privileged_fixtures_exclude_account_identity_and_report_their_limits(self):
        c=(ROOT/'tools/app_stability/native_ownership/policy-server.cjs').read_text()
        for collection in ['users','deda_sessions','deda_share_ids','deda_credentials','deda_account_profiles']:
            self.assertNotIn('setDoc(doc(db,`'+collection+'/',c)
        self.assertIn('privilegedIdentitySeeds:false',c)
        self.assertIn('privilegedOwnershipHistoryFixtures:true',c)
        self.assertIn('physicalTwoPhonesTested:false',c)
        self.assertIn('historyHash',c)
    def test_native_workflow_never_deploys_and_only_exports_sanitized_json(self):
        c=(ROOT/'.github/workflows/deda-stability-owned-frame-current-policy-qa.yml').read_text()
        self.assertNotIn('firebase deploy',c);self.assertNotIn('DEDA_KEYSTORE',c)
        self.assertIn('firebase.readonly',c)
        upload=c[c.index('name: DEDA-NATIVE-OWNED-FRAMES-CURRENT-POLICY-SANITIZED'):]
        self.assertNotIn('.log',upload);self.assertNotIn('/*.apk',upload)

if __name__=='__main__':unittest.main()
