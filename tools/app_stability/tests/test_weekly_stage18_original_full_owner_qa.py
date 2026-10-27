"""Source-level original 100393 functional QA without touching real DEDA."""
import importlib.util
import json
import tempfile
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
def module(rel):
    p=ROOT/rel
    spec=importlib.util.spec_from_file_location(p.stem,p)
    obj=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

class DedaRealAppSandboxQa(unittest.TestCase):
    def test_protected_original_has_functional_qa_on_both_home_routes(self):
        original=module('tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py')
        bind13=module('tools/app_stability/app_package/bind_weekly_stage13.py')
        bind14=module('tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py')
        bind16=module('tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py')
        bind17=module('tools/app_stability/app_package/bind_weekly_private_trial_stage17.py')
        bind18=module('tools/app_stability/app_package/bind_weekly_full_qa_stage18.py')
        with tempfile.TemporaryDirectory() as temp:
            project=Path(temp)/'signed-original'
            source=original.restored(project)
            metadata=project/'internal-build-inputs.json'
            m=json.loads(metadata.read_text())
            m['flags']={'DEDA_STABILITY_STARTUP_METRICS':True}
            metadata.write_text(json.dumps(m))
            bind13.bind(project)
            bind14.bind(project)
            bind16.bind(project)
            bind17.bind(project)
            details=bind18.bind(project)
            self.assertTrue(details['allTenPlacesTestable'])
            self.assertTrue(details['sandboxDiamondExactlyOnce'])
            self.assertFalse(details['writesRealWallet'])
            self.assertFalse(details['writesRealXp'])
            self.assertFalse(details['writesFirestore'])
            m=json.loads(metadata.read_text())
            self.assertEqual(m['versionCode'],100393)
            self.assertEqual(m['package'],'com.diraq.ludo.d_iraq_ludo')
            page=(project/'lib/deda_weekly_leaderboard_page.dart').read_text()
            screen=(project/'lib/deda_weekly_leaderboard_safe_screen.dart').read_text()
            main=(project/'lib/main.dart').read_text()
            self.assertEqual(main.count('localTrialAccountKey:'),2)
            self.assertIn("child: const Text('فتح مختبر الدوري')",page)
            self.assertIn("DedaWeeklyQaFullTrialPage(",page)
            self.assertIn("privateQaAccountScope: widget.localTrialAccountKey",screen)
            self.assertIn("الترتيب قيد التحقق من الخادم",page)
            self.assertNotIn('FirebaseFirestore',(
                project/'lib/deda_weekly_qa_full_trial.dart').read_text())
            self.assertNotIn('FieldValue.increment(',(
                project/'lib/deda_weekly_qa_full_trial.dart').read_text())
            # Only previously approved ID prewarm modifies this base file.
            for name,hash_before in source.items():
                if name in ('lib/main.dart','lib/deda_verified_active_id_store.dart'):
                    continue
                self.assertEqual(original.sha(project/name),hash_before,name)
            with self.assertRaises(ValueError):
                bind18.bind(project)

    def test_production_repo_never_mutated(self):
        bind18=module('tools/app_stability/app_package/bind_weekly_full_qa_stage18.py')
        with self.assertRaises(ValueError):
            bind18.bind(ROOT)

if __name__=='__main__':
    unittest.main()
