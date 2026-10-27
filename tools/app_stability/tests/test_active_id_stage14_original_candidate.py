"""DEDA stage14: improve same-phone verified ID first paint safely."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]


def mod(path):
    path=ROOT/path
    spec=importlib.util.spec_from_file_location(path.stem,path)
    o=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(o)
    return o


class OriginalActiveIdentityPreload(unittest.TestCase):
    def test_original100388_to_100389_isolated_and_account_safe(self):
        restore=mod("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        stage13=mod("tools/app_stability/app_package/bind_weekly_stage13.py")
        stage14=mod("tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py")
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"DEDA-original-private-100389"
            before=restore.restored(root)
            stage13.bind(root)
            mid=json.loads((root/"internal-build-inputs.json").read_text())
            assert mid["versionCode"]==100388
            result=stage14.bind(root)
            updated=json.loads((root/"internal-build-inputs.json").read_text())
            self.assertEqual(updated["package"],"com.diraq.ludo.d_iraq_ludo")
            self.assertEqual(updated["versionCode"],100389)
            self.assertTrue(result["preloadedBeforeFirstFrame"])
            self.assertTrue(result["serverStillRevalidates"])
            self.assertFalse(updated["completeOwnerDelivery"])
            main=(root/"lib/main.dart").read_text()
            store=(root/"lib/deda_verified_active_id_store.dart").read_text()
            scope=(root/"lib/deda_qa32_active_account_scope.dart").read_text()
            self.assertLess(main.index("await DedaVerifiedActiveIdStore.preloadForUid(uid);"),
                            main.index("runApp(const DedaApp());"))
            self.assertIn("FirebaseAuth.instance.currentUser?.uid",main)
            self.assertIn("name != _prefsKey(saved.uid, saved.originalId)",store)
            self.assertIn("saved.uid != uid",store)
            self.assertIn("if (_memory.containsKey(key)) continue",store)
            self.assertIn("preloadForUid(String uid)",store)
            self.assertIn("DedaVerifiedActiveIdStore.confirmed(",scope)
            self.assertIn("DedaVerifiedActiveIdStore.restore(",scope)
            self.assertEqual(
                (root/"lib/deda_backend.dart").read_bytes(),
                (root/"lib/deda_backend.dart").read_bytes())
            for name,h in before.items():
                if name not in ("lib/main.dart","lib/deda_verified_active_id_store.dart"):
                    self.assertEqual(stage14.sha(root/name),h,name)
            self.assertEqual(main.count("const DedaWeeklyLeaderboardSafeScreen()"),2)
            self.assertEqual(updated["sourceHashes"]["lib/deda_verified_active_id_store.dart"],
                             stage14.sha(root/"lib/deda_verified_active_id_store.dart"))
            with self.assertRaises(ValueError):
                stage14.bind(root)

    def test_never_works_in_repo_or_untrusted_version(self):
        stage14=mod("tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py")
        with self.assertRaises(ValueError):
            stage14.bind(ROOT)
        restore=mod("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            restore.restored(root)
            with self.assertRaises(ValueError):
                stage14.bind(root)

if __name__=="__main__":
    unittest.main()
