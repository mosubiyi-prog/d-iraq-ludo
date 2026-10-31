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
    scope=one(scope,
        "import 'package:firebase_auth/firebase_auth.dart';",
        "import 'package:cloud_firestore/cloud_firestore.dart';\n"
        "import 'package:firebase_auth/firebase_auth.dart';",
        "owner verified direct registry read import")
    scope=one(scope,
        "import 'deda_stage71_free_owned_use_profile.dart';",
        "import 'deda_stage71_free_owned_use_profile.dart';\n"
        "import 'deda_stage71_free_manager_200_service.dart';",
        "exact selected identifier registry reference")
    # Stage71.active() already checks same owner, authenticated session,
    # selected registry entry and gifted receipt before it returns. Do NOT
    # repeat a full 200-item owned-list query and second _requireOriginal.
    # A single verified registry document is sufficient to determine color.
    scope=one(scope,
        """      final owned = await DedaStage71OwnedIdentifierService.owned(original);
      final matching = owned.where((row) => row.identifier == active).toList();
      if (matching.length != 1) throw StateError('alias-not-owned');
      color = matching.single.baseColor;""",
        """      final selected = await FirebaseFirestore.instance
          .collection(DedaStage71Admin200.registry).doc(active)
          .get(const GetOptions(source: Source.server));
      final verified = DedaStage71OwnedIdentifier.read(
          selected.id, selected.data() ?? {}, original);
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('alias-reader-account-switched');
      }
      color = verified.baseColor;""",
        "no redundant full 200 owned-ID fetch after Stage71 verified active")
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

    # Stage71 use() must NEVER block its already server-verified activation
    # on optional public alias publication. The initial selection, ownership
    # and gifted-receipt checks remain intact; we reuse the verified foil.
    stage_file="lib/deda_stage71_free_owned_use_profile.dart"
    stage=(project/stage_file).read_text()
    stage=one(stage,
        "import 'deda_qa32_spark_public_identifier_directory.dart';",
        "import 'deda_qa32_spark_public_identifier_directory.dart';\n"
        "import 'deda_active_id_public_sync_100409.dart';",
        "stage71 nonblocking projection module")
    stage=one(stage,
        """    final db=FirebaseFirestore.instance;
    if (identifier!=originalId) {
      final owner=await db.collection(DedaStage71Admin200.registry)""",
        """    final db=FirebaseFirestore.instance;
    String? verifiedFoil;
    if (identifier!=originalId) {
      final owner=await db.collection(DedaStage71Admin200.registry)""",
        "stage71 verified color belongs to existing owner registry")
    stage=one(stage,
        """      DedaStage71OwnedIdentifier.read(
        owner.id,owner.data() ?? {},originalId);""",
        """      verifiedFoil = DedaStage71OwnedIdentifier.read(
        owner.id,owner.data() ?? {},originalId).baseColor;""",
        "reuse existing server-verified active color")
    old_begin=stage.index("    // Spark owner publication only after original ID")
    old_end=stage.index(
        "    if (FirebaseAuth.instance.currentUser?.uid != uid) {\n"
        "      throw StateError('account-switched-before-use-notifier');",
        old_begin)
    stage=stage[:old_begin]+"""    // OPTIONAL sync. Stage71 use() already verified ownership, the gifted
    // receipt (if any), and persisted the current active ID. Do not delay the
    // immediate success notifier on a public display index network request.
    if (DedaQa32SparkPublicIdentifierDirectory.enabled &&
        FirebaseAuth.instance.currentUser?.uid == uid) {
      unawaited(DedaActiveIdPublicSync100409.publishAfterVerifiedRead(
        uid: uid, originalId: originalId, activeId: identifier,
        fixedColor: verifiedFoil,
      ));
    }
"""+stage[old_end:]
    (project/stage_file).write_text(stage)

    for path in (PUBLIC, ADMIN, SCOPE, stage_file):
        meta["sourceHashes"][path]=sha(project/path)
    meta["versionCode"]=100409
    meta["weekly100409SingleVerifiedIdentity"]={
        "oneStage71ServerConfirmedSource": True,
        "selectedIdSingleRegistryReadInsteadOfAllOwnedList": True,
        "profileCachedSameUidFirst": True,
        "publicAliasSyncAfterOwnerVerifiedReadOnly": True,
        "publicRuleGuardsOwnedIdAndColor": True,
        "managerOneStableReadSubscription": True,
        "managerOwnVerifiedIdRevisionRefresh": True,
        "stage71UseDoesNotWaitForPublicProjection": True,
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
