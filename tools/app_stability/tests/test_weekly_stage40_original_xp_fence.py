"""Stage40 tests: patch ONLY the immutable signed-original DEDA source COPY."""
import hashlib
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from tools.app_stability.app_package.bind_weekly_stage40_original_xp_fence import bind,REPO,sha

ARCHIVE=REPO/"tools/app_stability/100380-baseline.tar.gz"
MANIFEST=REPO/"tools/app_stability/100380-baseline-manifest.json"
MODULE=REPO/"lib/deda_stage40_original_level_xp_fence.dart"

class OriginalStage40Test(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="deda-stage40-private-")
        self.addCleanup(self.temp.cleanup)
        self.workspace=Path(self.temp.name)
        (self.workspace/"lib").mkdir()
        manifest=json.loads(MANIFEST.read_text())
        self.assertEqual(hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(),
                         manifest["archiveSHA256"])
        with tarfile.open(ARCHIVE,"r:gz") as tar:
            members=[m for m in tar.getmembers()
                     if m.isfile() and m.name=="lib/main.dart"]
            self.assertEqual(len(members),1)
            self.original=tar.extractfile(members[0]).read().decode("utf-8")
        self.assertEqual(hashlib.sha256(self.original.encode()).hexdigest(),
                         manifest["files"]["lib/main.dart"])
        self.main=self.workspace/"lib/main.dart"
        self.main.write_text(self.original)
    def test_actual_original_20xp_and_coins_guarded_before_first_write(self):
        result=bind(self.workspace)
        self.assertTrue(result["socialXpGuarded"])
        self.assertTrue(result["socialCoinsGuarded"])
        self.assertTrue(result["taskPointsGuarded"])
        code=self.main.read_text()
        guard="DedaStage40OriginalTaskXpFence.blockLocalTaskAndSocialReward"
        self.assertEqual(code.count(guard),3) # task + wallet + UI
        start=code.index("  static Future<void> awardTaskClaim(String taskId)")
        end=code.index("\n  static ",start+10)
        wallet=code[start:end]
        self.assertLess(wallet.index(guard),wallet.index("final xp = snapshot.xp + xpPerTaskClaim;"))
        self.assertLess(wallet.index(guard),wallet.index("final coins = snapshot.coins + coinsPerTaskClaim;"))
        self.assertLess(wallet.index(guard),wallet.index("await prefs.setString("))
        task=code[code.index("  static Future<DedaTaskEventResult> claimTaskReward("):
             code.index("  static Future<bool> isTaskRewardedAdBonusClaimed(")]
        self.assertLess(task.index(guard),task.index("awards[awardId] = award;"))
        self.assertLess(task.index(guard),task.index("await _writeState(prefs, accountKey, state);"))
        self.assertIn("totalPoints: await totalPoints(),",task)
        self.assertTrue((self.workspace/"lib/deda_stage40_original_level_xp_fence.dart").is_file())
        self.assertIn("defaultValue: false",MODULE.read_text())
        self.assertIn("static bool get blockLocalTaskAndSocialReward => privatePilot;",
                      MODULE.read_text())
        # Old original archive, backend and user's local preferences not touched.
        self.assertEqual(hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(),
                         json.loads(MANIFEST.read_text())["archiveSHA256"])
        self.assertNotEqual(sha(self.main),hashlib.sha256(self.original.encode()).hexdigest())
    def test_duplicate_bind_is_refused_without_overwriting_pristine_files(self):
        bind(self.workspace)
        already=sha(self.main)
        with self.assertRaisesRegex(ValueError,"pristine_private_workspace_required"):
            bind(self.workspace)
        self.assertEqual(sha(self.main),already)
    def test_missing_original_wallet_anchor_causes_no_partial_patch(self):
        text=self.original.replace("static const int xpPerTaskClaim = 20;",
                                   "static const int xpPerTaskClaim = 21;",1)
        self.main.write_text(text)
        before=sha(self.main)
        with self.assertRaisesRegex(ValueError,"not_original_social_wallet"):
            bind(self.workspace)
        self.assertEqual(sha(self.main),before)
        self.assertFalse((self.workspace/"lib/deda_stage40_original_level_xp_fence.dart").exists())
    def test_unreviewed_private_metadata_is_refused_before_mutation(self):
        meta={"package":"com.diraq.ludo.d_iraq_ludo","variant":"candidate",
              "financialRestoreEnabled":False,"completeOwnerDelivery":False,
              "productionExecutionPerformed":False,
              "sourceHashes":{"lib/main.dart":"0"*64}}
        (self.workspace/"internal-build-inputs.json").write_text(json.dumps(meta))
        with self.assertRaisesRegex(ValueError,"unreviewed_signed_private_source"):
            bind(self.workspace)
        self.assertEqual(self.main.read_text(),self.original)
    def test_verified_private_metadata_records_no_live_server_cutover(self):
        meta={"package":"com.diraq.ludo.d_iraq_ludo","variant":"candidate",
              "financialRestoreEnabled":False,"completeOwnerDelivery":False,
              "productionExecutionPerformed":False,
              "sourceHashes":{"lib/main.dart":sha(self.main)}}
        path=self.workspace/"internal-build-inputs.json"
        path.write_text(json.dumps(meta))
        bind(self.workspace)
        after=json.loads(path.read_text())
        self.assertTrue(after["weeklyStage40"]["originalPlus5WriterGuarded"])
        self.assertTrue(after["weeklyStage40"]["originalPlus20XpWriterGuarded"])
        self.assertTrue(after["weeklyStage40"]["originalPlus10SocialCoinsWriterGuarded"])
        self.assertFalse(after["weeklyStage40"]["realServerCutoverComplete"])
        self.assertFalse(after["weeklyStage40"]["oldApkWritersActuallyRevoked"])

if __name__=="__main__":unittest.main()
