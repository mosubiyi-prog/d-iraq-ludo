"""100427 manual production release cannot bypass real-device QA/lease."""
import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
import deda_100427_login_guard_manual_release as mod
class ManualReleaseTest(unittest.TestCase):
    def test_reject_default_empty(self):
        with self.assertRaisesRegex(RuntimeError,"NOT_APPROVED"):
            mod.safety_gate({})
    def test_reject_missing_device_proof(self):
        with self.assertRaisesRegex(RuntimeError,"MISSING"):
            mod.safety_gate({"DEDA_100427_OWNER_APPROVAL_PHRASE":mod.APPROVAL})
    def test_reject_unverified_policy_sha(self):
        env={"DEDA_100427_OWNER_APPROVAL_PHRASE":mod.APPROVAL}
        env.update({x:"YES" for x in mod.REQUIRED_FLAGS})
        with self.assertRaisesRegex(RuntimeError,"EXPECTED_LIVE_SHA"):
            mod.safety_gate(env)
    def test_approval_requires_every_flag_and_exact_fingerprint(self):
        env={"DEDA_100427_OWNER_APPROVAL_PHRASE":mod.APPROVAL,
             "DEDA_100427_EXPECTED_LIVE_SHA":"a"*64}
        env.update({x:"YES" for x in mod.REQUIRED_FLAGS})
        self.assertEqual(mod.safety_gate(env),"a"*64)
        env["DEDA_100427_OWNER_REAL_100340_PIN_QA"]="NO"
        with self.assertRaisesRegex(RuntimeError,"MISSING"):
            mod.safety_gate(env)
    def test_fingerprint_fail_closed_before_any_publish(self):
        from deda_100426_stage_live_session_guard_no_deploy import OLD, BEGIN, END
        sample=("rules_version = '2';\n"
             +BEGIN+"\n"
             +"allow create, update: if request.auth.uid == uid\n"
             +" && exists(/databases/$(database)/documents/deda_auth_attempts/$(uid))\n"
             +" && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.accountKey == request.resource.data.accountKey\n"
             +OLD+"\n    }\n"+END+"\n    }\n"
             +"    match /deda_share_ids/{id} {\n    }\n"
             +"    match /deda_weekly_direct_weeks/{id} {\n    }\n")
        candidate=mod.stage(sample)
        self.assertEqual(mod.exact_candidate(sample,candidate,mod.digest(sample)),
                         mod.digest(candidate))
        with self.assertRaisesRegex(RuntimeError,"CHANGED"):
            mod.exact_candidate(sample,candidate,"a"*64)
        with self.assertRaisesRegex(RuntimeError,"EXACT"):
            mod.exact_candidate(sample,candidate+"//tamper",mod.digest(sample))
    def test_release_workflow_is_manual_only_not_automatic(self):
        wf=(pathlib.Path(__file__).resolve().parents[1] /
            ".github/workflows/deda-100427-owner-device-approved-login-rules-only-manual.yml").read_text()
        self.assertIn("on:\\n  workflow_dispatch:",wf)
        self.assertNotIn("on:\\n  push:",wf)
        self.assertNotIn("schedule:",wf)
        self.assertIn("tested_real_play_100340_pin",wf)
        self.assertIn("tested_real_new_phone_pin",wf)
        self.assertIn("expected_published_rules_sha256",wf)
        self.assertIn("deda_100427_login_guard_manual_release.py deploy",wf)
        self.assertIn("deda_100427_login_guard_manual_release.py verify",wf)
        self.assertIn("100408_LEAGUE",wf.replace("Retest unchanged 100408 league/prizes permissions","100408_LEAGUE"))
if __name__=="__main__": unittest.main()
