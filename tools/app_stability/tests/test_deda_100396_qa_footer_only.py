"""Safe original 100396 footer annotation tests on temporary fake workspace."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
file=ROOT/"tools/app_stability/app_package/bind_weekly_100396_qa_footer_only.py"
spec=importlib.util.spec_from_file_location("deda_qa_footer",file)
plugin=importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

class FooterSafety(unittest.TestCase):
 def workspace(self,tmp):
  folder=Path(tmp)
  (folder/"lib").mkdir()
  screen=("import 'deda_weekly_private_trial_local_xp.dart';\n"
   "class TestScreen {\n"
   "  int? _privateTrialXp;\n"
   "  String? _privateTrialScope;\n"
   "  Future<void> _readPrivateTrial() async {\n"
   "    final points=await DedaWeeklyPrivateTrialLocalXp.read(scope);\n"
   "    if(!mounted || widget.localTrialAccountKey!=scope) return;\n"
   "    setState(() {\n"
   "      _privateTrialScope=scope;\n"
   "      _privateTrialXp=points;\n"
   "    });\n"
   "  }\n"
   "  void view() {\n"
   "      privateTrialXp: _privateTrialScope == widget.localTrialAccountKey\n"
   "          ? _privateTrialXp : null,\n"
   "  }\n"
   "}\n")
  page=("class ExistingLeaderboard {\n"
   "    this.privateTrialXp,\n"
   "  final int? privateTrialXp;\n"
   "  final originalFooter =\n"
   "    'فحص نقاط مهامي هذا الأسبوع: '\n"
   "                            '${widget.privateTrialXp} XP محلياً؛ '\n"
   "                            'لا ترتيب حقيقياً ولا جوائز.';\n"
   "}\n")
  (folder/plugin.SC).write_text(screen)
  (folder/plugin.PG).write_text(page)
  (folder/"pubspec.yaml").write_text("name: d_iraq_ludo\n")
  (folder/"pubspec.lock").write_text("packages: {}\n")
  sha_map={p:sha(folder/p) for p in [
   plugin.SC,plugin.PG,"pubspec.yaml","pubspec.lock"]}
  data={"versionCode":100396,"completeOwnerDelivery":False,
   "financialRestoreEnabled":False,
   "weeklyStage29VerifiedXpBinding":{
    "phoneAndTabletRoutes":2,"observationalOnly":True,
    "independentProofIssuerActive":False,"noWalletChanges":True},
   "sourceHashes":sha_map}
  (folder/"internal-build-inputs.json").write_text(json.dumps(data))
  return folder,sha_map
 def test_footer_only(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder,original=self.workspace(tmp)
   result=plugin.bind(folder)
   screen=(folder/plugin.SC).read_text()
   page=(folder/plugin.PG).read_text()
   self.assertIn("readOwnUnverifiedXp(scope)",screen)
   self.assertIn("مراقبة خادمية تجريبية",page)
   self.assertIn("فحص نقاط مهامي هذا الأسبوع",page)
   self.assertTrue(result["statusOnlyNotLayout"])
   self.assertFalse(result["noPrizes"] is False)
   self.assertEqual(sha(folder/"pubspec.yaml"),original["pubspec.yaml"])
   self.assertEqual(sha(folder/"pubspec.lock"),original["pubspec.lock"])
   self.assertEqual(json.loads(
    (folder/"internal-build-inputs.json").read_text())["versionCode"],100396)
 def test_stale_prepatched_ui_is_rejected_without_overwrite(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder,_=self.workspace(tmp)
   s=folder/plugin.SC
   s.write_text(s.read_text().replace(
     "    final points=await DedaWeeklyPrivateTrialLocalXp.read(scope);",
     "    final points = 900000;"))
   unchanged=sha(s)
   with self.assertRaises(ValueError):
    plugin.bind(folder)
   self.assertEqual(sha(s),unchanged)
 def test_missing_owner_qa_approval_fails_closed(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder,_=self.workspace(tmp)
   path=folder/"internal-build-inputs.json"
   x=json.loads(path.read_text())
   x["weeklyStage29VerifiedXpBinding"]["observationalOnly"]=False
   path.write_text(json.dumps(x))
   with self.assertRaises(ValueError):
    plugin.bind(folder)

if __name__=="__main__":
 unittest.main()
