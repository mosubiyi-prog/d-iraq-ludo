"""Stage the reviewed account-ownership guard in the EXACT reconstructed 100420 source.

Run after 100418 binding, before any APK build. No network, Firebase, signing or
live-account access. Refuses drift and changes only one Dart helper in an
isolated ephemeral assembly directory (never the repository or baseline).
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REL = "lib/deda_owner18_original_account_proof.dart"
OLD = """        route['ownerUid'] is String &&
        (route['ownerUid'] as String).isNotEmpty;"""
NEW = """        route['ownerUid'] is String &&
        (route['ownerUid'] as String).isNotEmpty &&
        // A replacement device has a different anonymous Firebase UID.
        // Its own server account projection must explicitly bind the immutable
        // original DEDA ID; a matching phone/accountKey alone is not proof.
        (route['ownerUid'] == uid || account['sharePersonalId'] == original);"""


def sha(source: bytes) -> str:
    return hashlib.sha256(source).hexdigest()


def stage(target: Path) -> None:
    target = target.resolve(strict=True)
    if target == ROOT or ROOT in target.parents or target in ROOT.parents:
        raise ValueError("REFUSE_TO_CHANGE_REPOSITORY_OR_BASELINE")
    metadata = target / "internal-build-inputs.json"
    if not metadata.is_file():
        raise ValueError("MISSING_RECONSTRUCTED_SOURCE_MANIFEST")
    flags = json.loads(metadata.read_text())
    if not (flags.get("versionCode") == 100418
            and flags.get("package") == "com.diraq.ludo.d_iraq_ludo"
            and flags.get("weekly100418Legacy340OwnerOnlyAuthReadCandidate", {}).get("adminPrizesBalancesUnchanged") is True
            and flags.get("weekly100414FinalThree", {}).get("neverRekeyPremiumOrFriends") is True
            and flags.get("completeOwnerDelivery") is False
            and flags.get("financialRestoreEnabled") is False):
        raise ValueError("NOT_VERIFIED_100420_PRE_BUILD_ASSEMBLY")
    path = target / REL
    current = path.read_text()
    reviewed = (ROOT / REL).read_text()
    if reviewed.count(NEW) != 1 or current.count(OLD) != 1:
        raise ValueError("ORIGINAL_GUARD_PATCH_ANCHOR_CHANGED")
    # The real 100420 assembly has additional section-lifecycle guards.
    # Keep ALL of those wrappers; never replace the whole helper with a
    # historical repository copy that would drop session cancellation.
    def one(source: str, before: str, after: str) -> str:
        if source.count(before) != 1:
            raise ValueError("RECONSTRUCTED_LIFECYCLE_WRAPPER_DRIFT")
        return source.replace(before, after, 1)

    baseline = reviewed.replace(NEW, OLD)
    baseline = "import 'deda_section_operation_context.dart';\\n" + baseline
    baseline = one(baseline,
        "final docs = await Future.wait([",
        "final docs = await DedaSectionOperationContext.wait(() => Future.wait([")
    baseline = one(baseline, "    ]);\\n    final account =",
        "    ]));\\n    final account =")
    baseline = one(baseline,
        "      await db\\n          .collection('deda_lab_frame_receipts')",
        "      await DedaSectionOperationContext.wait(() => db\\n          .collection('deda_lab_frame_receipts')")
    baseline = one(baseline,
        "          .get(const GetOptions(source: Source.server));\\n    }\\n    if (FirebaseAuth.instance",
        "          .get(const GetOptions(source: Source.server)));\\n    }\\n    if (FirebaseAuth.instance")
    if baseline != current:
        import difflib
        print("SAFE_STOP_UNREVIEWED_ASSEMBLED_GUARD_DRIFT")
        print("".join(difflib.unified_diff(
            current.splitlines(keepends=True), baseline.splitlines(keepends=True),
            fromfile="verified_100420", tofile="expected_reconstructed",
        ))[:5000])
        raise ValueError("UNEXPECTED_100420_MODULE_CHANGE")
    patched = current.replace(OLD, NEW, 1)
    if patched.replace(NEW, OLD) != current:
        raise ValueError("RECONSTRUCTED_GUARD_ONLY_CHANGE_VIOLATION")
    if flags["sourceHashes"].get(REL) != sha(current.encode()):
        raise ValueError("ORIGINAL_SOURCE_HASH_MISMATCH")
    if "DedaOwner18OriginalAccountProof.verify" not in (
            target / "lib/deda_account_choice_firebase.dart").read_text():
        raise ValueError("NO_RECONSTRUCTED_CALLSITE_TO_GUARD")
    if "signInAnonymously()" not in (target / "lib/deda_pin_auth.dart").read_text():
        raise ValueError("AUTH_FLOW_DRIFT_REVIEW_REQUIRED")
    # Make exactly one source-only change inside the isolated candidate.
    path.write_text(patched)
    flags["sourceHashes"][REL] = sha(patched.encode())
    flags["weekly100421CanonicalOriginalIdGuardSourceOnly"] = {
        "real100420Assembly": True, "sourceOnly": True,
        "noFirebaseChanges": True, "noWalletRestore": True,
        "noApkOrPlay": True, "liveTwoDeviceValidationPending": True,
    }
    metadata.write_text(json.dumps(flags, ensure_ascii=False, indent=2) + "\n")
    print("PASS_100421_EXACT_RECONSTRUCTED_SOURCE_CANONICAL_GUARD_PRESENT")
    print("NO_APK_NO_FIREBASE_NO_PLAY_NO_FINANCIAL_RESTORE")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage_100421_original_account_guard_no_build.py ASSEMBLY_DIR")
    stage(Path(sys.argv[1]))
