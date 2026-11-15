"""DEDA profile original-ID step 1: immediate permanent canonical card display.

Run only after the complete 100448 isolated assembly and its verified original
picker binding. This is a PRESENTATION-ONLY change: the original-ID card
already exists as the exact Stage71 fallback in the owner's personal profile.
Leave premium inventory, grant/use, Firebase, friend/share/league code untouched.
The future decorative-only premium-ID policy belongs to step 2, NOT here.
No protected source or live server may be mutated.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STAGE = "lib/deda_stage71_free_owned_use_profile.dart"
MAIN = "lib/main.dart"
FOIL_CLASS = "class _DedaStage71ActiveProfileFoilState"
BUILD = "  @override\n  Widget build(BuildContext context) {"
ORIGINAL_ONLY_BUILD = """  @override
  Widget build(BuildContext context) {
    // The existing fallback holds the permanent canonical original ID.
    // It paints immediately from the phone-derived ID, without premium
    // verification, and preserves the original copy action/card choice.
    // Premium grants, active selections and server records are untouched.
    // Decorative premium presentation is deferred to approved step 2.
    return widget.fallback;
  }
}
"""


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bind(project: Path) -> None:
    project = project.resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("STEP1_PROTECTED_SOURCE_REFUSED")
    meta_path = project / "internal-build-inputs.json"
    meta = json.loads(meta_path.read_text())
    if (meta.get("package") != "com.diraq.ludo.d_iraq_ludo"
            or meta.get("financialRestoreEnabled") is not False
            or meta.get("completeOwnerDelivery") is not False
            or meta.get("productionExecutionPerformed") is not False
            or meta.get("originalIdReturnOwnerVerified20261115", {}).get(
                "premiumInventoryCannotBlockOriginal") is not True
            or meta.get("weekly100410UnifiedActiveId", {}).get(
                "profileFoilNoIndependentActiveAndOwnedReader") is not True
            or "profileOriginalImmediateStep1" in meta):
        raise ValueError("STEP1_EXPECTED_VERIFIED_100448_ASSEMBLY_MISSING")
    for relative in (STAGE, MAIN):
        p = project / relative
        if not p.is_file() or meta["sourceHashes"].get(relative) != digest(p):
            raise ValueError("STEP1_UNVERIFIED_INPUT_" + relative)
    main = (project / MAIN).read_text()
    # The Stage71 fallback chain is the owner's existing original-ID card.
    # Its personal ID and copy action predate the premium display.
    for required in (
        "DedaStage71ActiveProfileFoil(",
        "DedaStage71FreeProfileFoil(",
        "DedaPoint14VerifiedProfileSlot(",
        "String get _personalDedaId =>",
        "Future<void> _copyDedaId() async",
    ):
        count = main.count(required)
        if count != 1 and not (required == "DedaPoint14VerifiedProfileSlot("
                               and count >= 1):
            raise ValueError("STEP1_CANONICAL_PROFILE_CHAIN_CHANGED_"
                             + required + "_count_" + str(count))
    if "final id = _personalDedaId;" not in main:
        raise ValueError("STEP1_CANONICAL_COPY_CHANGED")

    stage_file = project / STAGE
    source = stage_file.read_text()
    if source.count(FOIL_CLASS) != 1:
        raise ValueError("STEP1_FOIL_NOT_UNIQUE")
    start = source.index(FOIL_CLASS)
    state_class = source[start:]
    if state_class.count(BUILD) != 1 or not state_class.endswith("  }\n}\n"):
        raise ValueError("STEP1_FOIL_CLASS_CHANGED")
    build_start = state_class.index(BUILD)
    old_build = state_class[build_start:]
    for expected in (
        "DedaVerifiedActiveIdStore.read(uid,widget.originalId)",
        "DedaPremiumIdCard(",
        "return widget.fallback;",
        "جارِ تأكيد الآيدي...",
    ):
        if expected not in old_build:
            raise ValueError("STEP1_PREMIUM_PRESENTATION_UNEXPECTED_" + expected)
    # Keep all historic checks/services, grants and state handlers unchanged;
    # replace precisely the last owner-profile widget build method.
    updated = source[:start + build_start] + ORIGINAL_ONLY_BUILD
    if updated.count("return widget.fallback;") < 1:
        raise ValueError("STEP1_CANONICAL_CARD_NOT_RESTORED")
    stage_file.write_text(updated)
    meta["sourceHashes"][STAGE] = digest(stage_file)
    meta["profileOriginalImmediateStep1"] = {
        "canonicalIdDisplayedWithoutPremiumProof": True,
        "canonicalIdSource": "DedaBackend.personalShareIdForPhone",
        "existingOriginalCardAndCopyPreserved": True,
        "premiumOwnershipAndSelectionUntouched": True,
        "friendsLeagueShareCodeUntouched": True,
        "premiumDecorativePresentationDeferredToStep2": True,
        "completeOwnerDelivery": False,
        "apkBuilt": False,
        "firebaseOrPlayChanged": False,
        "realPhoneVerificationPending": True,
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    print("PASS_STEP1_PROFILE_ORIGINAL_ID_IMMEDIATE_SOURCE_ONLY")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    bind(parser.parse_args().project)
