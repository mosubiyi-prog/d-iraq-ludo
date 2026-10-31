#!/usr/bin/env python3
"""Apply and verify ONLY pretested DEDA 100408 prize policy addition.

Production preserving; refuse any drift in published policy between the
preflight emulator and deploy. No point, wallet, purchase or prize writes.
"""
import importlib.util, json, os, pathlib, sys
spec = importlib.util.spec_from_file_location(
    "deda_100408_readonly", pathlib.Path(__file__).with_name(
        "deda_100408_live_prize_rules_readonly_preflight.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
ROOT = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp"))
IDENTITY = ROOT / "deda-100408-firestore-sa.json"

def validate():
    obj = json.loads(mod.REPORT.read_text())
    assert obj.get("readOnly") and obj.get("noOtherPolicyModifications")
    assert obj.get("firebaseDeployPerformed") is False
    assert obj.get("project") == mod.PROJECT
    assert obj.get("candidateSha") == mod.digest(mod.RULES.read_text())
    return obj

def credential_file():
    raw = os.environ.get("PRIMARY") or os.environ.get("FALLBACK") or ""
    info = json.loads(raw)
    assert info.get("type") == "service_account"
    assert info.get("project_id") == mod.PROJECT
    IDENTITY.write_text(raw)
    IDENTITY.chmod(0o600)

def predeploy():
    previous = validate()
    name, live = mod.current_rules(mod.session())
    assert previous["ruleset"] == name, "PRODUCTION_RELEASE_CHANGED_ABORT"
    assert previous["previousSha"] == mod.digest(live), "LIVE_POLICY_CHANGED_ABORT"
    assert "match /deda_weekly_direct_prize_plans/" not in live
    assert "function exactWeeklyLeagueGeneralManager()" in live
    credential_file()
    print("100408_ADDITIVE_RULES_PREDEPLOY_LIVE_UNCHANGED=True")
    print("100408_NO_WALLET_XP_OR_PRIZE_WRITES=True")

def verify():
    obj = validate()
    name, live = mod.current_rules(mod.session())
    assert name != obj["ruleset"], "LIVE_RELEASE_NOT_UPDATED"
    assert obj["candidateSha"] == mod.digest(live), "LIVE_POLICY_READBACK_MISMATCH"
    assert "match /deda_weekly_direct_prize_plans/" in live
    assert live.count("prizes_increase") == 1
    print("100408_PRIZE_PLAN_ONLY_FIRESTORE_ACTIVATION=VERIFIED")
    print("100408_ACTUAL_PAYOUT_WORKER_STILL_DISABLED=True")

if __name__ == "__main__":
    steps = {"predeploy": predeploy, "verify": verify}
    assert sys.argv[1:] and sys.argv[1] in steps
    steps[sys.argv[1]]()
