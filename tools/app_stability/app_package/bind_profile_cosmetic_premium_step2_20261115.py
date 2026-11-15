"""DEDA step 2 — present verified owned premium as profile-only decoration.

Run AFTER 100448 reconstruction, original-owner picker binder and STEP1.
Replace only the OLD profile's owned-ID panel and premium hero state with
local cosmetic counterparts at the SAME UI insertion points.
No original-ID routing changes, server Use, active-alias writes or APK build.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STAGE = "lib/deda_stage71_free_owned_use_profile.dart"
MAIN = "lib/main.dart"
COSMETIC = "lib/deda_cosmetic_premium_profile_20261115.dart"
PANEL_START = "class _DedaStage71OwnedIdsPanelState"
PANEL_END = "/// On the user's personal hero"
FOIL_START = "class _DedaStage71ActiveProfileFoilState"
COSMETIC_IMPORT = "import 'deda_cosmetic_premium_profile_20261115.dart';\n"

COSMETIC_PANEL = """class _DedaStage71OwnedIdsPanelState
    extends State<DedaStage71OwnedIdsPanel> {
  @override
  Widget build(BuildContext context) =>
      DedaCosmeticPremiumSelectorPanel20261115(
        originalId: widget.originalId,
      );
}

"""

COSMETIC_FOIL = """class _DedaStage71ActiveProfileFoilState
    extends State<DedaStage71ActiveProfileFoil> {
  @override
  Widget build(BuildContext context) =>
      DedaCosmeticPremiumProfileFoil20261115(
        originalId: widget.originalId,
        fallback: widget.fallback,
      );
}
"""


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bind(project: Path) -> None:
    project = project.resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("STEP2_PROTECTED_SOURCE_REFUSED")
    meta_path = project / "internal-build-inputs.json"
    meta = json.loads(meta_path.read_text())
    step1 = meta.get("profileOriginalImmediateStep1", {})
    if (meta.get("package") != "com.diraq.ludo.d_iraq_ludo"
            or meta.get("completeOwnerDelivery") is not False
            or meta.get("financialRestoreEnabled") is not False
            or meta.get("productionExecutionPerformed") is not False
            or step1.get("canonicalIdDisplayedWithoutPremiumProof") is not True
            or step1.get("premiumOwnershipAndSelectionUntouched") is not True
            or "profileCosmeticPremiumStep2" in meta):
        raise ValueError("STEP2_VERIFIED_STEP1_ASSEMBLY_REQUIRED")
    for relative in (STAGE, MAIN):
        item = project / relative
        if not item.is_file() or sha(item) != meta["sourceHashes"].get(relative):
            raise ValueError("STEP2_ASSEMBLY_HASH_MISMATCH_" + relative)
    stage_path = project / STAGE
    source = stage_path.read_text()
    if (source.count(PANEL_START) != 1 or
            source.count(PANEL_END) != 1 or
            source.count(FOIL_START) != 1 or
            source.count(COSMETIC_IMPORT) != 0 or
            source.count("class DedaStage71ActiveProfileFoil") != 1 or
            source.count("class DedaStage71OwnedIdsPanel") != 1):
        raise ValueError("STEP2_EXACT_PROFILE_MARKERS_REQUIRED")
    left = source.index(PANEL_START)
    right = source.index(PANEL_END)
    foil = source.index(FOIL_START)
    if not 0 < left < right < foil:
        raise ValueError("STEP2_PROFILE_BOUNDARIES_CHANGED")
    old_panel = source[left:right]
    old_foil = source[foil:]
    if not all(x in old_panel for x in (
        "DedaStage71OwnedIdentifierService.use(",
        "DedaStage71OwnedIdentifierService.owned(original)",
        "if (originalVerified)",
        "_verifiedUid",
    )):
        raise ValueError("STEP2_OLD_SERVER_USE_PANEL_MISMATCH")
    if not (old_foil.count("return widget.fallback;") == 1 and
            "DedaUnifiedActiveId100410.ensureOwner(widget.originalId)" in old_foil
            and "DedaPremiumIdCard(" not in old_foil and
            old_foil.endswith("  }\n}\n")):
        # STEP1 already removed ONLY foil build; prior network subscriptions
        # still exist. Step2 removes those subscriptions and obsolete listeners.
        raise ValueError("STEP2_EXPECTED_STEP1_FOIL_NOT_FOUND")
    # No old selectors are left within the two profile widgets; the protected
    # Stage71 service is byte-identical, so its 200-ID grants are untouched.
    preserved_service = source[:left]
    updated = (
        preserved_service
        + COSMETIC_PANEL
        + source[right:foil]
        + COSMETIC_FOIL
    )
    anchor = "import 'deda_verified_active_id_store.dart';\n"
    if updated.count(anchor) != 1:
        raise ValueError("STEP2_IMPORT_ANCHOR_CHANGED")
    updated = updated.replace(anchor, anchor + COSMETIC_IMPORT, 1)
    # Never alter the data/service region even if a future commit moves files.
    if updated.split(COSMETIC_IMPORT, 1)[1].split(PANEL_START, 1)[0] != (
        source.split(anchor, 1)[1].split(PANEL_START, 1)[0]
    ):
        raise ValueError("STEP2_PROTECTED_SERVICE_CHANGED")
    local_source = ROOT / COSMETIC
    if not local_source.is_file():
        raise ValueError("STEP2_COSMETIC_IMPLEMENTATION_MISSING")
    module = local_source.read_text()
    for required in (
        "DedaCosmeticPremiumEntitlements20261115.accepted",
        "DedaStage71OwnedIdentifierService.owned(original)",
        "DedaStage74IdGiftService.isReceived(",
        "SharedPreferences.getInstance()",
        "DedaPremiumIdCard(",
        "return widget.fallback;",
        "DedaCosmeticPremiumChoice20261115.select(",
    ):
        if required not in module:
            raise ValueError("STEP2_COSMETIC_SAFETY_MISSING_" + required)
    for forbidden in (
        "DedaStage71OwnedIdentifierService.use(",
        ".collection(DedaStage71OwnedIdentifierService.activeCollection)",
        "DedaVerifiedActiveIdStore.confirmed(",
        "DedaQa32SparkPublicIdentifierDirectory.publishOwnerVerified(",
        "FirebaseFirestore.instance",
        "Clipboard.setData(",
    ):
        if forbidden in module:
            raise ValueError("STEP2_COSMETIC_MUST_NOT_ACTIVATE_GLOBAL_ALIAS")
    copied = project / COSMETIC
    if copied.exists():
        raise ValueError("STEP2_REFUSE_COSMETIC_OVERWRITE")
    shutil.copy2(local_source, copied)
    stage_path.write_text(updated)
    meta["sourceHashes"][COSMETIC] = sha(copied)
    meta["sourceHashes"][STAGE] = sha(stage_path)
    meta["profileCosmeticPremiumStep2"] = {
        "originalVisibleWithoutCosmeticChoice": True,
        "premiumOldProfileLocationPreserved": True,
        "premiumActivationLocalOnly": True,
        "premiumActivationRequiresServerOwnedGiftProof": True,
        "sameUidAndOriginalIdScoped": True,
        "noGlobalActiveAliasWrites": True,
        "noPremiumCopyTapOrRouting": True,
        "canonicalAccountAndMainUnchanged": True,
        "owned200RegistryAndAdminUntouched": True,
        "previousGlobalAliasResolutionRequiresStep3Audit": True,
        "firebaseOrPlayChanged": False,
        "apkBuilt": False,
        "phoneVerificationPending": True,
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
    print("PASS_STEP2_PROFILE_PREMIUM_COSMETIC_ONLY_NO_GLOBAL_USE")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("project", type=Path)
    bind(ap.parse_args().project)
