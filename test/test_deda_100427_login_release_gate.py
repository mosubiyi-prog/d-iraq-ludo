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
if __name__=="__main__": unittest.main()
