"""Regression guard: only the trusted-install branch in deda_sessions may change."""
import pathlib
import sys
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"tools"))
import deda_100426_stage_live_session_guard_no_deploy as mod
class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.sample=("rules_version = '2';\nservice cloud.firestore {\n"
            "    match /deda_sessions/{uid} {\n"
            "        allow create, update: if signedIn() && request.auth.uid == uid\n"
            "          && exists(/databases/$(database)/documents/deda_auth_attempts/$(uid))\n"
            "          && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.accountKey == request.resource.data.accountKey\n"
            "          && (true\n" + mod.OLD + ");\n    }\n"
            "    match /deda_account_profiles/{accountKey} {\n    }\n"
            "    match /deda_share_ids/{id} {\n    }\n"
            "    match /deda_weekly_direct_weeks/{id} {\n    }\n}\n")
    def test_reversible_only_exact_branch(self):
        staged=mod.stage(self.sample)
        self.assertEqual(staged.replace(mod.NEW,mod.OLD,1),self.sample)
        self.assertEqual(staged.count("100426: trusted-install alone"),1)
    def test_drift_fails_closed(self):
        with self.assertRaises(AssertionError):
            mod.stage(self.sample.replace("trustedInstallIds", "trustedIds"))
    def test_pin_proof_or_session_anchor_missing_rejected(self):
        with self.assertRaises(AssertionError):
            mod.stage(self.sample.replace("deda_auth_attempts/", "deda_auth_proofs/"))
        with self.assertRaises(AssertionError):
            mod.stage(self.sample.replace("match /deda_sessions/{uid}","match /another/{uid}"))
if __name__=="__main__":unittest.main()
