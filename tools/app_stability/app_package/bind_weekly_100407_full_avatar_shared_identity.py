"""DEDA 100407 owner feedback: remove double-frame clipping on all league avatars.

Prepared, signed-original 100406 workspace only. Keeps original painter and
immutable XP/diamond/account routing. Never edit the owner-accepted repository.
"""
from pathlib import Path
import argparse,hashlib,json

ROOT=Path(__file__).resolve().parents[3]
PAGE="lib/deda_weekly_leaderboard_page.dart"
MAIN="lib/main.dart"
SCOPE="lib/deda_qa32_active_account_scope.dart"
WRAPPER="lib/deda_weekly_owner_pilot_bridge.dart"
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
    # Stage18 is the accepted luxury podium with extra shimmer, a white
    # border and two shadows. Keep its styling only for empty fallback slots;
    # do not wrap a player's verified purchased frame in this second ring.
    begin=page.index("  Widget podium(")
    finish=page.index("  Widget rankingTable(",begin)
    podium=page[begin:finish]
    podium=once(podium,
        "                        padding: EdgeInsets.all(3 * scale),",
        """                        padding: player != null && player.canShowEquippedFrame &&
                                widget.drawOriginalEquippedAvatar != null
                            ? EdgeInsets.zero : EdgeInsets.all(3 * scale),""",
        "verified podium padding")
    podium=once(podium,
        """                        decoration: BoxDecoration(
                          shape: BoxShape.circle,""",
        """                        decoration: player != null && player.canShowEquippedFrame &&
                                widget.drawOriginalEquippedAvatar != null
                            ? null
                            : BoxDecoration(
                          shape: BoxShape.circle,""",
        "verified podium standalone frame")
    page=page[:begin]+podium+page[finish:]
    assert page.count("drawOriginalEquippedAvatar!")>=2
    (project/PAGE).write_text(page)
    # The original 100406 stable profile already validates Stage71 ownership,
    # but its UI waits for repeated serial reads on every widget mount.
    # Apply only AFTER the protected baseline has been reconstructed.
    # A same-UID, Stage71-confirmed last display may be painted immediately;
    # ordinary authenticated server revalidation always follows it.
    scope=(project/SCOPE).read_text()
    scope=once(scope,
        "import 'deda_stage71_free_owned_use_profile.dart';",
        "import 'deda_stage71_free_owned_use_profile.dart';\n"
        "import 'deda_verified_active_id_store.dart';",
        "shared active-ID store import after prepare")
    if "    if (_proof != null) setState(() => _proof = null);" not in scope:
        at=scope.find("Future<void> _load() async")
        raise ValueError("100407 generated scope differs: "+repr(scope[at:at+1800]))
    scope=once(scope,
        """    if (_proof != null) setState(() => _proof = null);
    if (dedaStabilityIdentityPilot && _paused) return;""",
        """    // Same-account refresh must not flash the retired original ID.
    // On UID/original change, clear the previous account proof immediately.
    if (_proof != null && (uid == null ||
        !_proof!.verifiedFor(uid, original))) {
      setState(() => _proof = null);
    }
    if (dedaStabilityIdentityPilot && _paused) return;""",
        "no old-ID flicker on verified same account")
    scope=once(scope,
        """    try {
      Future<DedaQa32ActiveAccountIdentity> readVerified() =>""",
        """    // Presentation only. A fresh device with no previously confirmed
    // per-UID state waits for the ordinary verified owner server read.
    if (widget._source is _FirebaseIdentitySource) {
      final saved = DedaVerifiedActiveIdStore.read(uid, original);
      if (saved != null && saved.wellFormed &&
          _currentUid() == uid && widget.originalId == original &&
          (_proof?.displayId != saved.displayId ||
           _proof?.fixedColor != saved.fixedColor)) {
        setState(() => _proof = DedaQa32ActiveAccountIdentity(
          uid: uid, originalId: original,
          displayId: saved.displayId, fixedColor: saved.fixedColor,
        ));
      }
    }
    try {
      Future<DedaQa32ActiveAccountIdentity> readVerified() =>""",
        "prefill verified same-UID ID only")
    scope=once(scope,
        """      setState(() => _proof = next);
    } catch (_) {""",
        """      if (widget._source is _FirebaseIdentitySource) {
        // A genuine Stage71-verified read updates the ONE UI source shared
        // with league. Never treats this cache as purchase or auth authority.
        DedaVerifiedActiveIdStore.confirmed(
          uid: uid, originalId: original, displayId: next.displayId,
          fixedColor: next.fixedColor,
        );
      }
      setState(() => _proof = next);
    } catch (_) {""",
        "server-confirmed alias projection into shared owner cache")
    (project/SCOPE).write_text(scope)

    # A single stable notifier combines real XP with the existing
    # server-confirmed Stage71 display-ID revision. Do not instantiate the
    # merged Listenable on every Flutter rebuild (would reset league state).
    main=(project/MAIN).read_text()
    old_signal="          refreshSignal: DedaSocialProgressWallet.xpNotifier,\n"
    if main.count(old_signal)!=2:
        raise ValueError("both official league refresh callbacks required")
    main=main.replace(old_signal,
        "          refreshSignal: dedaWeeklyXpAndVerifiedIdRefresh,\n")
    main=once(main,"enum DedaMapStyle {",
        """// UI-only. XP source remains original level XP; active ID source remains
// server-confirmed Stage71, never a separate leaderboard identifier.
final Listenable dedaWeeklyXpAndVerifiedIdRefresh = Listenable.merge([
  DedaSocialProgressWallet.xpNotifier,
  DedaVerifiedActiveIdStore.revision,
  DedaWeeklyOwnerPilotBridge.standingRefresh,
]);

enum DedaMapStyle {""",
        "one shared active-ID + XP refresh notifier")
    (project/MAIN).write_text(main)
    # Same canonical task receipt retry: first paint is never blocked by up to
    # eight sequential Firebase network writes; update after true delivery.
    wrapper=(project/WRAPPER).read_text()
    wrapper=once(wrapper,
        "import 'deda_weekly_firestore_direct_bridge.dart';",
        "import 'package:flutter/foundation.dart';\n"
        "import 'deda_weekly_firestore_direct_bridge.dart';",
        "reactive score notifier import")
    wrapper=once(wrapper,
        "  const DedaWeeklyOwnerPilotBridge._();",
        """  const DedaWeeklyOwnerPilotBridge._();
  static Listenable get standingRefresh =>
      DedaWeeklyFirestoreDirectBridge.standingRefresh;""",
        "single standings completion notifier")
    (project/WRAPPER).write_text(wrapper)
    bridge=(project/BRIDGE).read_text()
    if ("Future.wait<Map<String, dynamic>>(" not in bridge or
        "DedaVerifiedActiveIdStore.read(authUid, pid)" not in bridge or
        "standingRefresh.value += 1" not in bridge or
        "final ref = scores(w.id).doc(person.id);" not in bridge):
        raise ValueError("single confirmed ID / parallel safe score bridge missing")
    for name in (PAGE, BRIDGE, MAIN, WRAPPER, SCOPE):
        meta["sourceHashes"][name]=sha(project/name)
    meta["versionCode"]=100407
    meta["weekly100407OwnerCorrections"]={
        "alreadyServerConfirmedSameUidDisplayCacheReused":True,
        "profileServerReadSeedsSharedCache":True,
        "leagueAutoRefreshesOnOwnerVerifiedIdChange":True,
        "scoreReadNeverBlocksOnEightPendingRetries":True,
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
