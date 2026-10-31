"""DEDA 100407 owner feedback: remove double-frame clipping on all league avatars.

Prepared, signed-original 100406 workspace only. Keeps original painter and
immutable XP/diamond/account routing. Never edit the owner-accepted repository.
"""
from pathlib import Path
import argparse,hashlib,json

ROOT=Path(__file__).resolve().parents[3]
PAGE="lib/deda_weekly_leaderboard_page.dart"
BRIDGE="lib/deda_weekly_firestore_direct_bridge.dart"

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def once(source, before, after, name):
    if source.count(before)!=1:
        raise ValueError("100407-source-anchor-drift: "+name)
    return source.replace(before,after,1)

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("never mutate owner accepted DEDA checkout")
    manifest=project/"internal-build-inputs.json"
    meta=json.loads(manifest.read_text())
    if (meta.get("versionCode")!=100406 or
        meta.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        meta.get("financialRestoreEnabled") is not False or
        meta.get("weekly100406DisplayFixes",{}).get("originalDedaFramedAvatarPassedThroughBothOfficialRoutes") is not True):
        raise ValueError("signed SHA-verified 100406 original required")
    for path,digest in meta["sourceHashes"].items():
        if not (project/path).is_file() or sha(project/path)!=digest:
            raise ValueError("unverified 100406 input "+path)
    page=(project/PAGE).read_text()
    page=once(page,
        """          padding: EdgeInsets.all(math.max(1.5, avatarSize * .065)),
          child: player != null && player.canShowEquippedFrame &&
""",
        """          padding: player != null && player.canShowEquippedFrame &&
                  widget.drawOriginalEquippedAvatar != null
              ? EdgeInsets.zero
              : EdgeInsets.all(math.max(1.5, avatarSize * .065)),
          child: player != null && player.canShowEquippedFrame &&
""",
        "row avatar inner padding")
    page=once(page,
        """          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [gold, Color(0xFFA9701C), gold]),
            boxShadow: [BoxShadow(color: gold.withValues(alpha: .25),
                blurRadius: avatarSize * .25)],
          ),
""",
        """          // The purchased frame is the OUTER decoration. Do not draw
          // a second circle around it or squeeze the full selected avatar.
          decoration: player != null && player.canShowEquippedFrame &&
                  widget.drawOriginalEquippedAvatar != null
              ? null
              : BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [gold, Color(0xFFA9701C), gold]),
                  boxShadow: [BoxShadow(color: gold.withValues(alpha: .25),
                      blurRadius: avatarSize * .25)],
                ),
""",
        "row avatar double border")
    page=once(page,
        """                        padding: EdgeInsets.all(3 * scale),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            accent, accent.withValues(alpha: .55), accent]),
                          boxShadow: [BoxShadow(
                            color: accent.withValues(alpha: .50),
                            blurRadius: 13 * scale)],
                        ),
""",
        """                        padding: player != null && player.canShowEquippedFrame &&
                                widget.drawOriginalEquippedAvatar != null
                            ? EdgeInsets.zero : EdgeInsets.all(3 * scale),
                        decoration: player != null && player.canShowEquippedFrame &&
                                widget.drawOriginalEquippedAvatar != null
                            ? null
                            : BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [
                                  accent, accent.withValues(alpha: .55), accent]),
                                boxShadow: [BoxShadow(
                                  color: accent.withValues(alpha: .50),
                                  blurRadius: 13 * scale)],
                              ),
""",
        "top three duplicate frame and inset")
    assert page.count("drawOriginalEquippedAvatar!")>=2
    (project/PAGE).write_text(page)
    bridge=(project/BRIDGE).read_text()
    if ("Future.wait<Map<String, dynamic>>(" not in bridge or
        "DedaVerifiedActiveIdStore.read(authUid, pid)" not in bridge or
        "final ref = scores(w.id).doc(person.id);" not in bridge):
        raise ValueError("single confirmed ID / parallel safe score bridge missing")
    for name in (PAGE, BRIDGE):
        meta["sourceHashes"][name]=sha(project/name)
    meta["versionCode"]=100407
    meta["weekly100407OwnerCorrections"]={
        "alreadyServerConfirmedSameUidDisplayCacheReused":True,
        "scoreAndOriginalRouteNeverChanged":True,
        "independentAliasAndEquipmentReadsParallel":True,
        "neverBorrowAppearanceFromViewer":True,
        "originalEquippedFrameOutsideWithoutDuplicateRing":True,
        "fullAvatarWithoutExtraContainerInset":True,
        "pointsAndWalletChanged":False,
        "newProductionPrizePayout":False,
        "ownerPhoneAndTabletVerificationPending":True,
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    return meta["weekly100407OwnerCorrections"]

if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("workspace",type=Path)
    print(json.dumps(bind(cli.parse_args().workspace),ensure_ascii=False))
