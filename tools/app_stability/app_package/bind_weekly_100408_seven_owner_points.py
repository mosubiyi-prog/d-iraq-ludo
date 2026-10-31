"""100408 ordered owner corrections. Apply to verified assembled 100407 QA only.

Point 1: instant same-UID previously verified display ID, reconciled by Stage71.
Points 2-7: applied separately below once each prior point has passed.
No changes to a signed rollback reference, XP, wallet, or Google Play.
"""
import argparse, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
SCOPE="lib/deda_qa32_active_account_scope.dart"
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def one(s,old,new,label):
    if s.count(old)!=1:
        raise ValueError("100408 safety anchor mismatch: "+label+" count "+str(s.count(old)))
    return s.replace(old,new,1)
def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("owner-approved source is read only")
    meta_file=project/"internal-build-inputs.json"
    meta=json.loads(meta_file.read_text())
    if meta.get("versionCode")!=100407 or meta.get("package")!="com.diraq.ludo.d_iraq_ludo" or meta.get("financialRestoreEnabled") is not False or meta.get("weekly100407OwnerCorrections",{}).get("profileAlreadyUsesVerifiedOwnerStore") is not True:
        raise ValueError("100407 verified output required before 100408")
    for path,digest in meta["sourceHashes"].items():
        if not (project/path).is_file() or sha(project/path)!=digest:
            raise ValueError("verified baseline changed "+path)
    scope=(project/SCOPE).read_text()
    if "import 'deda_verified_active_id_store.dart';" not in scope or "DedaVerifiedActiveIdStore.confirmed(" not in scope:
        raise ValueError("verified owner-only Stage71 cache is missing")
    scope=one(scope,
        """    return widget.builder(context, proof);
  }
}""",
        """    // Same-UID server-confirmed UI display is restored before the slow
    // independent account/ownership refresh completes. NEVER use this to
    // authorize transactions, gifts, friendships, grants, or change a UID.
    return ValueListenableBuilder<int>(
      valueListenable: DedaVerifiedActiveIdStore.revision,
      builder: (context, _, __) {
        final owner = _currentUid();
        final valid = owner != null &&
            _proof?.verifiedFor(owner, widget.originalId) == true;
        final cached = owner != null &&
                widget._source is _FirebaseIdentitySource
            ? DedaVerifiedActiveIdStore.read(owner, widget.originalId)
            : null;
        final shown = valid ? _proof
            : cached == null ? null : DedaQa32ActiveAccountIdentity(
                uid: owner!, originalId: widget.originalId,
                displayId: cached.displayId, fixedColor: cached.fixedColor,
              );
        return widget.builder(context, shown);
      },
    );
  }
}""",
        "point1 same UID cached profile paint")
    (project/SCOPE).write_text(scope)
    meta["sourceHashes"][SCOPE]=sha(project/SCOPE)
    meta["versionCode"]=100408
    meta["weekly100408OwnerSevenPoints"]={
      "point1VerifiedCacheBeforeServerRecheck": True,
      "point1OriginalAccountKeyImmutable": True,
      "point1OtherAccountCacheForbidden": True,
      "point1OwnerPhoneTestPending": True,
      "point2MaintenanceBanner": False,
      "point3WrongTransitionalBalances": False,
      "point4SlowLeagueFirstPaint": False,
      "point5PodiumNumberOpacity": False,
      "point6AdminAliasPresentation": False,
      "point7ManagerPausedPrizeEditor": False,
      "payoutActivated": False,
      "walletOrXPModified": False,
    }
    meta_file.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["weekly100408OwnerSevenPoints"]
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("workspace",type=Path)
    print(json.dumps(bind(parser.parse_args().workspace),ensure_ascii=False))
