"""DEDA 100409: ONE verified owner ID with optional secured public projection.

Applied only after proven 100408 build is reconstructed. No double ownership
resolver, no account rekey, no XP/gem/award change, and no Google Play deploy.
"""
import argparse, hashlib, json, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCOPE = "lib/deda_qa32_active_account_scope.dart"
PUBLIC = "lib/deda_active_id_public_sync_100409.dart"
ADMIN = "lib/deda_admin_league_active_id.dart"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError("100409-anchor-not-exact: " + label + " count=" + str(s.count(old)))
    return s.replace(old, new, 1)

def bind(workspace):
    project=Path(workspace).resolve()
    if project == ROOT or ROOT in project.parents:
        raise ValueError("DO_NOT_EDIT_OWNER_ACCEPTED_REPO")
    manifest=project/"internal-build-inputs.json"
    meta=json.loads(manifest.read_text())
    if (meta.get("versionCode") != 100408 or
        meta.get("package") != "com.diraq.ludo.d_iraq_ludo" or
        meta.get("financialRestoreEnabled") is not False or
        not all(meta.get("weekly100408OwnerSevenPoints",{}).get(k) is True
          for k in ("point1VerifiedCacheBeforeServerRecheck",
                    "point2MaintenanceBanner",
                    "point3WrongTransitionalBalances",
                    "point4SlowLeagueFirstPaint",
                    "point5PodiumNumberOpacity",
                    "point6AdminAliasPresentation",
                    "point7ManagerPausedPrizeEditor"))):
        raise ValueError("100408-full-seven-points-verified-baseline-required")
    for file,digest in meta["sourceHashes"].items():
        if not (project/file).is_file() or sha(project/file) != digest:
            raise ValueError("100409-baseline-hash-changed: " + file)

    shutil.copy2(ROOT/PUBLIC,project/PUBLIC)
    shutil.copy2(ROOT/"lib/deda_admin_league_active_id_100409.dart",project/ADMIN)
    scope=(project/SCOPE).read_text()
    # Keep 100408's previously tested Stage71 verified owner reader intact.
    # No second ownership resolver; only attach public projection after success.
    scope=one(scope,
        "import 'deda_verified_active_id_store.dart';",
        "import 'deda_verified_active_id_store.dart';\n"
        "import 'deda_active_id_public_sync_100409.dart';",
        "only verified owner profile import")
    anchor="DedaVerifiedActiveIdStore.confirmed("
    if scope.count(anchor)!=1:
        raise ValueError("single Stage71-confirmed owner ID callback required")
    begin=scope.index(anchor)
    end=scope.find(");",begin)
    if end<0 or end-begin>600:
        raise ValueError("100409-confirmed callback unexpectedly changed")
    # Only the verified owner callback starts optional publication.
    # The network call cannot delay / clear / replace the visible profile ID.
    scope=scope[:end+2]+"""
        unawaited(DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
          uid: uid, originalId: original, activeId: next.displayId,
          fixedColor: next.fixedColor,
        ));"""+scope[end+2:]
    (project/SCOPE).write_text(scope)

    # Do not patch Stage71 purchase/use/grant code: its assembled variant
    # differs across existing owner stages. The verified profile callback
    # above independently repairs the public display projection. All
    # original Stage71 account ownership, receipt, and real ID use behavior
    # remains bit-for-bit untouched.
    stage_file="lib/deda_stage71_free_owned_use_profile.dart"
    stage=(project/stage_file).read_text()
    print("STAGE71_BUILD_USE_MARKER",stage.find("static Future<void> use("))
    print("STAGE71_BUILD_SPARK_MARKER",stage.find("Spark owner publication only"))
    print("STAGE71_BUILD_USE_CONTEXT",repr(stage[max(0,stage.find("static Future<void> use(")):][:2000]))
    
    for path in (PUBLIC, ADMIN, SCOPE, stage_file):
        meta["sourceHashes"][path]=sha(project/path)
    meta["versionCode"]=100409
    meta["weekly100409SingleVerifiedIdentity"]={
        "oneStage71ServerConfirmedSource": True,
        "noUnreviewedOwnerRegistryQueryChange": True,
        "profileCachedSameUidFirst": True,
        "publicAliasSyncAfterOwnerVerifiedReadOnly": True,
        "publicRuleGuardsOwnedIdAndColor": True,
        "managerOneStableReadSubscription": True,
        "managerOwnVerifiedIdRevisionRefresh": True,
        "stage71ActivationLogicUnchanged": True,
        "managerReadErrorAndSixSecondBound": True,
        "noRetiredOriginalFallbackOnUnknownAlias": True,
        "accountKeysUnchanged": True,
        "xpWalletAndPrizesUnchanged": True,
        "phoneTestPending": True,
        "productionPublicProjectionRequiresSecureDartFlag": True,
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["weekly100409SingleVerifiedIdentity"]

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("workspace",type=Path)
    print(json.dumps(bind(parser.parse_args().workspace),ensure_ascii=False))
