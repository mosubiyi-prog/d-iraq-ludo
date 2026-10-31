"""100408 point 1 / seven: speed up same-owner server-verified active-ID read.

Run ONLY after signed-original 100407 assembled in an isolated workspace.
The verified owner store and session invalidation of 100407 are preserved.
No Firestore writes, no account routes/XP/diamonds changes, no Play deploy.
"""
from pathlib import Path
import argparse, hashlib, json

ROOT = Path(__file__).resolve().parents[3]
SCOPE = "lib/deda_qa32_active_account_scope.dart"
OWNED = "lib/deda_stage71_free_owned_use_profile.dart"

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def once(text,old,new,reason):
    if text.count(old)!=1: raise ValueError("100408 point 1 source mismatch "+reason)
    return text.replace(old,new,1)

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("never mutate accepted DEDA original checkout")
    manifest=project/"internal-build-inputs.json"
    meta=json.loads(manifest.read_text())
    if (meta.get("versionCode")!=100407 or
        meta.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        meta.get("financialRestoreEnabled") is not False or
        meta.get("weekly100407OwnerCorrections",{}).get("profileAlreadyUsesVerifiedOwnerStore") is not True):
        raise ValueError("verified 100407 assembled source required")
    for name,digest in meta["sourceHashes"].items():
        if not (project/name).is_file() or sha(project/name)!=digest:
            raise ValueError("100407 source hash drift "+name)
    # Replace the owner header's expensive "active + query 200 owned IDs"
    # with the SAME server owner proof + one active record + one owned record.
    # Gifts still require server receipt and repeated same-UID checks.
    owned_path=project/OWNED
    owned=owned_path.read_text()
    start=owned.index("  static Future<String> active(String originalId) async {")
    end=owned.index("  static Future<void> use(",start)
    source=owned[start:end]
    assert source.count("_requireOriginal(originalId)") == 1
    assert source.count("DedaStage74IdGiftService.isReceived(")==1
    assert source.count("DedaStage71OwnedIdentifier.read(")==1
    assert source.count("return current;")==1
    optimized=source.replace("static Future<String> active(",
        "static Future<({String id, String? color})> activeWithColor(")
    optimized=once(optimized,"if (!doc.exists) return originalId;",
        "if (!doc.exists) return (id: originalId, color: null);","no active")
    import re
    optimized, count = re.subn(
        r'if\\s*\\(\\s*current\\s*==\\s*originalId\\s*\\)\\s*return\\s+originalId\\s*;',
        'if (current == originalId) return (id: originalId, color: null);',
        optimized, count=1)
    if count != 1:
        at=optimized.find("final current=")
        raise ValueError("active current source differs "+repr(optimized[at:at+450]))
    optimized=once(optimized,"    return current;",
        "    return (id: current, color: owner.baseColor);","verified active color")
    assert "source: Source.server" in optimized
    assert "account-switched-after-active-gift-receipt" in optimized
    owned=owned[:start]+optimized+"\n"+owned[start:]
    owned_path.write_text(owned)

    # Existing account-shared DedaVerifiedActiveIdStore will still cache and
    # notify on success, while stale different-UID work is rejected.
    scope_path=project/SCOPE
    scope=scope_path.read_text()
    before="""    final active = await DedaStage71OwnedIdentifierService.active(original);
    String? color;
    if (active != original) {
      final owned = await DedaStage71OwnedIdentifierService.owned(original);
      final matching = owned.where((row) => row.identifier == active).toList();
      if (matching.length != 1) throw StateError('alias-not-owned');
      color = matching.single.baseColor;
    }
    return DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: original, displayId: active, fixedColor: color,
    );"""
    after="""    // Read just the verified active entitlement, not the full owned-ID store.
    // Stage71 still checks the canonical account + gift receipt server-side.
    final verified =
        await DedaStage71OwnedIdentifierService.activeWithColor(original);
    if (currentUid != uid) throw StateError('active-id-owner-rotated');
    return DedaQa32ActiveAccountIdentity(
      uid: uid, originalId: original,
      displayId: verified.id, fixedColor: verified.color,
    );"""
    scope=once(scope,before,after,"owner header verified optimized read")
    assert "DedaVerifiedActiveIdStore.confirmed(" in scope
    assert "DedaVerifiedActiveIdStore.restore(uid, original)" in scope
    scope_path.write_text(scope)
    for name in (SCOPE,OWNED): meta["sourceHashes"][name]=sha(project/name)
    meta["versionCode"]=100408
    meta["weekly100408Point1"]={
      "verifiedServerOwnedActiveAndColorOnePass":True,
      "noFullOwnedRegistryQueryForDisplay":True,
      "cacheSharedWithLeague":True,
      "checksOriginalAccountAndGiftReceipt":True,
      "noOldIdFlashOnSameUidRefresh":True,
      "freshPhoneRequiresServerProof":True,
      "latencyTargetSecondsPendingPhoneMeasurement":True,
      "originalXPOrDiamondsModified":False,
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["weekly100408Point1"]

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("workspace",type=Path)
    print(json.dumps(bind(p.parse_args().workspace),ensure_ascii=False))
