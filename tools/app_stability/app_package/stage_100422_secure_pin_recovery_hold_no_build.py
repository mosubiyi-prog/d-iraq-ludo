"""Source-only stage for 100422 secure PIN preflight on exact 100421 assembly.

Only copies opt-in recovery bridge and adds an unused recovery-specific entry
to DedaPinAuth; the normal login, registration, production Firebase Rules and
signed 100420 APK remain exactly unchanged.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HELPER = "lib/deda_secure_pin_preflight.dart"
TEST = "test/deda_secure_pin_preflight_contract_test.dart"
PIN = "lib/deda_pin_auth.dart"
IMPORT_ANCHOR = "import 'package:cloud_firestore/cloud_firestore.dart';\n"
LOGIN_ANCHOR = "  static Future<Map<String, dynamic>> signIn({\n"
ENTRY = """  // Explicit preflight for a FUTURE, controlled server-authorized recovery.
  // HOLD only: does not create a DEDA session or restore any data.
  static Future<String> verifyRecoveryIdentityWithServer({
    required String phone,
    required String pin,
  }) async {
    await _ensureAnonymousSession();
    return DedaSecurePinPreflight.verifyCanonicalHold(phone: phone, pin: pin);
  }

"""


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def stage(target: Path) -> None:
    target = target.resolve(strict=True)
    if target == ROOT or ROOT in target.parents or target in ROOT.parents:
        raise ValueError("REFUSE_REPOSITORY_OR_BASELINE_MUTATION")
    manifest = target / "internal-build-inputs.json"
    flags = json.loads(manifest.read_text())
    if not (flags.get("versionCode") == 100418
            and flags.get("financialRestoreEnabled") is False
            and flags.get("completeOwnerDelivery") is False
            and flags.get("weekly100421CanonicalOriginalIdGuardSourceOnly", {}).get("real100420Assembly") is True):
        raise ValueError("MISSING_VERIFIED_100421_PREBUILD_ASSEMBLY")
    original = (target / PIN).read_text()
    if original.count(IMPORT_ANCHOR) != 1 or original.count(LOGIN_ANCHOR) != 1:
        raise ValueError("UNREVIEWED_LOGIN_SOURCE_DRIFT")
    # The exact 100420 assembled login differs from the historical repository
    # helper. We preserve it byte-for-byte outside the two addition anchors.
    if "class DedaPinAuth" not in original:
        raise ValueError("ORIGINAL_PIN_AUTH_CLASS_MISSING")
    if "DedaSecurePinPreflight" in original:
        raise ValueError("BRIDGE_ALREADY_APPLIED")
    if flags["sourceHashes"].get(PIN) != sha(original.encode()):
        raise ValueError("LOGIN_SOURCE_HASH_MISMATCH")
    updated = original.replace(IMPORT_ANCHOR,
                               IMPORT_ANCHOR + "import 'deda_secure_pin_preflight.dart';\n", 1)
    updated = updated.replace(LOGIN_ANCHOR, ENTRY + LOGIN_ANCHOR, 1)
    if updated.count("await _provePin(accountKey: accountKey, pin: pin);") != original.count("await _provePin(accountKey: accountKey, pin: pin);"):
        raise ValueError("NORMAL_SIGN_IN_MUST_NOT_CHANGE")
    for rel in [HELPER, TEST]:
        src = ROOT / rel
        dst = target / rel
        data = src.read_bytes()
        if dst.exists():
            # prepare.py already stages some unit tests; only accept an
            # exact byte-for-byte match, never overwrite unrelated content.
            if dst.read_bytes() != data:
                raise ValueError("UNREVIEWED_PREEXISTING_STAGED_FILE_" + rel)
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
        flags["sourceHashes"][rel] = sha(data)
    (target / PIN).write_text(updated)
    flags["sourceHashes"][PIN] = sha(updated.encode())
    flags["weekly100422SecurePinRecoveryPreflightSourceOnly"] = {
        "serverCallableExportedInRepository": True,
        "productionCallableDeployed": False,
        "normalSignInUnchanged": True,
        "recoveryEntryOptInAndHoldOnly": True,
        "canonicalOriginalServerHoldOnly": True,
        "walletAndIdentityMigrationEnabled": False,
        "noApkOrFirebaseOrPlay": True,
    }
    manifest.write_text(json.dumps(flags, ensure_ascii=False, indent=2) + "\n")
    print("PASS_100422_REAL_100420_ASSEMBLY_RECOVERY_HOLD_ENTRY_STAGED")
    print("NO_PRODUCTION_LOGIN_CHANGE_NO_APK_NO_FIREBASE_NO_PLAY")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage_100422_secure_pin_recovery_hold_no_build.py DIR")
    stage(Path(sys.argv[1]))
