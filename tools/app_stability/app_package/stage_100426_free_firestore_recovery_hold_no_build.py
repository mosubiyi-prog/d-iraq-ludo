"""Opt-in source only: Spark Firestore recovery HOLD in verified 100420 assembly.

No changes to original login, account creation, PIN functions, session, rules,
financial state, signed APK or Play. Invoke AFTER 100422 source-only staging.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "lib/deda_pin_auth.dart"
HELPER = "lib/deda_free_firestore_recovery_hold.dart"
TEST = "test/deda_free_firestore_recovery_hold_contract_test.dart"
IMPORT = "import 'package:cloud_firestore/cloud_firestore.dart';\n"
ANCHOR = "  static Future<Map<String, dynamic>> signIn({\n"
ENTRY = """  // Opt-in free Firestore enrollment only; signIn/createAccount unchanged.
  // This cannot grant assets, restore user records, or migrate an ID.
  static Future<void> enrollOriginalRecoveryOnThisDevice({
    required String phone,
    required String pin,
    required String originalId,
  }) async {
    await _ensureAnonymousSession();
    final key = accountKeyForPhone(phone);
    await _provePin(accountKey: key, pin: pin);
    await DedaFreeFirestoreRecoveryHold.enrollOnOriginalDevice(
      accountKey: key, originalId: originalId);
  }

  // Opt-in correct-PIN proof of original ID from a replacement Android UID.
  // No new DEDA session, source UID replacement or wallet access.
  static Future<String> verifyFreeRecoveryIdentityOnNewDevice({
    required String phone,
    required String pin,
  }) async {
    await _ensureAnonymousSession();
    final key = accountKeyForPhone(phone);
    await _provePin(accountKey: key, pin: pin);
    return DedaFreeFirestoreRecoveryHold.verifyOnNewDevice(accountKey: key);
  }

"""

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def stage(target: Path) -> None:
    target = target.resolve(strict=True)
    if target == ROOT or ROOT in target.parents or target in ROOT.parents:
        raise ValueError("REFUSE_REPOSITORY_OR_BASELINE_MUTATION")
    manifest = target / "internal-build-inputs.json"
    flags = json.loads(manifest.read_text())
    if (flags.get("versionCode") != 100418
            or flags.get("financialRestoreEnabled") is not False
            or flags.get("completeOwnerDelivery") is not False
            or flags.get("weekly100422SecurePinRecoveryPreflightSourceOnly", {}).get(
                "normalSignInUnchanged") is not True):
        raise ValueError("REQUIRE_VERIFIED_100422_SOURCE_AND_FINANCIAL_HOLD")
    raw = (target / PIN).read_text()
    if raw.count(IMPORT) != 1 or raw.count(ANCHOR) != 1:
        raise ValueError("UNREVIEWED_LOGIN_SOURCE_DRIFT")
    if "DedaSecurePinPreflight" not in raw or "DedaFreeFirestoreRecoveryHold" in raw:
        raise ValueError("MISSING_PREVIOUS_CHECKPOINT_OR_ALREADY_APPLIED")
    if flags.get("sourceHashes", {}).get(PIN) != sha(raw.encode()):
        raise ValueError("ORIGINAL_LOGIN_SOURCE_HASH_MISMATCH")
    updated = raw.replace(
        IMPORT, IMPORT + "import 'deda_free_firestore_recovery_hold.dart';\n", 1)
    updated = updated.replace(ANCHOR, ENTRY + ANCHOR, 1)
    for mandatory in ("static Future<Map<String, dynamic>> signIn({",
                      "static Future<Map<String, dynamic>> createAccount({",
                      "static Future<void> _provePin({",
                      "static Future<void> _openSession("):
        if updated.count(mandatory) != raw.count(mandatory):
            raise ValueError("PRODUCTION_LOGIN_MUST_NOT_CHANGE")
    for rel in (HELPER, TEST):
        data = (ROOT / rel).read_bytes()
        dest = target / rel
        if dest.exists() and dest.read_bytes() != data:
            raise ValueError("STAGED_FILE_CONFLICT_" + rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        flags["sourceHashes"][rel] = sha(data)
    (target / PIN).write_text(updated)
    flags["sourceHashes"][PIN] = sha(updated.encode())
    flags["weekly100426FreeFirestoreRecoveryHoldSourceOnly"] = {
        "actualLiveRulesMergeEmulatorPassed": True,
        "productionRulesDeployed": False,
        "usesCloudFunctions": False,
        "normalSignInUnchanged": True,
        "bootstrapRequiresOriginalUidAndFreshPin": True,
        "recoveryIsHoldOnly": True,
        "walletAndIdentityMigrationEnabled": False,
        "apkBuilt": False,
        "noFirebaseOrPlayChanges": True,
    }
    manifest.write_text(json.dumps(flags, ensure_ascii=False, indent=2) + "\n")
    print("PASS_100426_REAL_100420_SOURCE_OPT_IN_FREE_FIRESTORE_HOLD")
    print("NO_PRODUCTION_LOGIN_CHANGE_NO_APK_NO_FIREBASE_WRITES_NO_ASSET_RESTORE")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage_100426_free_firestore_recovery_hold_no_build.py DIR")
    stage(Path(sys.argv[1]))
