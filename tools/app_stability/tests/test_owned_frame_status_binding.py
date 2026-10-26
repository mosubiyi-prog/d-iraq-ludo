import sys
import tarfile
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/app_stability'))
from bind_owned_frame_status import bind_source
from bind_auth_runtime import body_range,tokens,pairs


class OwnedFrameStatusBindingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as t:
            cls.original=t.extractfile('lib/main.dart').read().decode()

    def test_error_is_visible_retryable_and_does_not_clear_verified_items(self):
        updated=bind_source(self.original)
        self.assertIn("Key('deda_owned_frames_unavailable')",updated)
        self.assertIn("Key('deda_owned_frames_loading')",updated)
        self.assertIn('onPressed: _loadingOwnedFrames ? null : _loadOwnedFrames',updated)
        a,b,_,_=body_range(updated,'_loadOwnedFrames',after=updated.index('class _DedaEditProfilePageState '))
        load=updated[a:b+1]
        self.assertIn('if (_loadingOwnedFrames) return;',load)
        self.assertNotIn('_serverVerifiedPaidStyles.clear',load)
        self.assertNotIn('buyOnce(',load)
        self.assertNotIn('.spend(',load)
        self.assertIn('finally',load)
        self.assertIn('.timeout(const Duration(seconds: 12))',load)
        self.assertIn('if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser?.uid == null)',load)
        pairs(tokens(updated))

    def test_edit_save_equip_purchase_and_all_other_pages_are_unchanged(self):
        updated=bind_source(self.original)
        for method in ['_equipOwnedFrame','_save']:
            values=[]
            for source in [self.original,updated]:
                a,b,_,_=body_range(source,method,after=source.index('class _DedaEditProfilePageState '))
                values.append(source[a:b+1])
            self.assertEqual(*values)
        start=self.original.index('class _DedaEditProfilePageState ')
        end=self.original.index('\nclass ',start+1)
        self.assertTrue(updated.startswith(self.original[:start]))
        self.assertTrue(updated.endswith(self.original[end:]))

    def test_drift_and_double_binding_are_rejected(self):
        updated=bind_source(self.original)
        with self.assertRaises(ValueError):bind_source(updated)
        with self.assertRaisesRegex(ValueError,'exact original'):
            bind_source(self.original.replace('/* Keep unpaid frames locked until server proof succeeds. */','drift'))

    def test_real_restoration_adds_status_before_lifetime_guards(self):
        source=(ROOT/'tools/restore_deda_stability_baseline.py').read_text()
        self.assertLess(source.index('bind_owned_frame_status(output)'),source.index('        bind_directory(output)'))


if __name__=='__main__':unittest.main()
