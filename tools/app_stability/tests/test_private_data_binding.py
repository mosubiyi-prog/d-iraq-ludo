import importlib.util
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
from bind_private_data import bind_source, bind_quiz
from bind_auth_runtime import body_range, tokens, pairs


class PrivateDataBindingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as t:
            cls.main = t.extractfile('lib/main.dart').read().decode()
            cls.quiz = t.extractfile('lib/traffic_quiz_page.dart').read().decode()

    def test_all_original_nonfinancial_reads_and_writes_are_bound(self):
        main, quiz = bind_source(self.main), bind_quiz(self.quiz)
        for text in ['DedaPrivateDataBridge.readList(prefs, key)',
                     'DedaPrivateDataBridge.readString(prefs, _placesKey)',
                     'DedaPrivateDataBridge.readString(prefs, _draftKey)',
                     'DedaPrivateDataBridge.write(prefs, _draftKey, null)',
                     'const DedaPrivateDataPage()']:
            self.assertIn(text, main)
        for key in ['_seenKey', '_dailyIdsKey', '_progressKey', '_completedKey']:
            self.assertIn('DedaPrivateDataBridge.', quiz)
            self.assertNotIn('prefs.getStringList('+key+')', quiz)
            self.assertNotIn('prefs.getString('+key+')', quiz)
            self.assertNotIn('prefs.getBool('+key+')', quiz)
        pairs(tokens(main)); pairs(tokens(quiz))

    def test_wallets_auth_roles_rewards_and_quiz_callbacks_stay_byte_exact(self):
        updated = bind_source(self.main)
        for name in ['DedaPreferences', 'DedaTaskEngine', 'DedaDiamondsWallet', 'DedaSocialProgressWallet', 'DedaStyleInventory']:
            def section(source):
                start = source.index('class '+name+' {')
                end = source.index('\nclass ', start+1)
                return source[start:end]
            self.assertEqual(section(self.main), section(updated), name)
        quiz = bind_quiz(self.quiz)
        for method in ['_confirmAnswer', '_next']:
            a,b,_,_ = body_range(self.quiz,method); c,d,_,_ = body_range(quiz,method)
            self.assertEqual(self.quiz[a:b+1],quiz[c:d+1])

    def test_double_binding_or_source_drift_is_rejected(self):
        for function, source, anchor in [(bind_source,self.main,'prefs.getStringList(key)'),
                                        (bind_quiz,self.quiz,'prefs.getBool(_completedKey)')]:
            with self.assertRaises(ValueError): function(function(source))
            with self.assertRaises(ValueError): function(source.replace(anchor,'drifted'))

    def test_transport_has_no_login_payment_or_ownership_mutations(self):
        bridge = (ROOT/'lib/deda_private_data_bridge.dart').read_text()
        for marker in ['.signIn', '.signOut', '.spend(', '.claimReward(', '.buyOnce(', 'setUserName(']:
            self.assertNotIn(marker, bridge)
        self.assertIn('Source.server', bridge)
        self.assertIn('DedaFirebaseAccountChoiceIo().verifyOwner', bridge)
        self.assertIn('tx.set(ref, data); tx.set(history, data)', bridge)
        self.assertIn('if (old != beforeBundle)', bridge)
        self.assertIn('if (payload == null)', bridge)
        self.assertIn('backupConfirmed()', bridge)

    def test_restorer_and_package_include_the_actual_bound_files(self):
        source = (ROOT/'tools/restore_deda_stability_baseline.py').read_text()
        self.assertIn('bind_private_data(output)', source)
        for name in ['deda_private_data_sync.dart','deda_private_data_bridge.dart','deda_private_data_page.dart']:
            self.assertIn(name, source)


if __name__ == '__main__': unittest.main()
