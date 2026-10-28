"""Wire original DEDA read-only public-profile navigation to BOTH league
home entries in a temporary, source-hash-verified Stage61 workspace ONLY.

This is a real Flutter source integration, NOT an actual verified standings
backend. No friendship writes, leaderboard XP, live awards, deploy or APK.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
META = "internal-build-inputs.json"
ADDITION = "lib/deda_weekly_original_public_profile_readonly.dart"
SOURCE = "lib/deda_weekly_leaderboard_safe_screen.dart"
MAIN = "lib/main.dart"

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def once(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError("WEEKLY_ORIGINAL_SOCIAL_ANCHOR_" + label + "_" + str(s.count(old)))
    return s.replace(old, new, 1)

def bind(project):
    project = Path(project).resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("Never modify repository or original 100342")
    record = project/META
    if not record.is_file():
        raise ValueError("Source-hash-verified Stage61 candidate required")
    meta = json.loads(record.read_text())
    s61 = meta.get("weeklyStage61", {})
    if (meta.get("versionCode") != 100396 or
        meta.get("variant") != "candidate" or
        meta.get("package") != "com.diraq.ludo.d_iraq_ludo" or
        meta.get("completeOwnerDelivery") is not False or
        meta.get("financialRestoreEnabled") is not False or
        meta.get("productionExecutionPerformed") is not False or
        s61.get("officialHomeRoutesScoped") != 2 or
        s61.get("originalAnonymousUidAndAccountCaptured") is not True or
        s61.get("verifiedGlobalRankingsAvailable") is not False or
        s61.get("actualWeeklyPrizePayoutEnabled") is not False or
        not meta.get("sourceHashes")):
        raise ValueError("Stage61 account isolation or original source invalid")
    old_hashes = meta["sourceHashes"]
    for name, digest in old_hashes.items():
        if not (project/name).is_file() or sha(project/name) != digest:
            raise ValueError("Unverified original source " + name)
    if (project/ADDITION).exists():
        raise ValueError("Refuse overwrite of read-only original social viewer")
    if sha(ROOT/SOURCE) == sha(project/SOURCE):
        raise ValueError("Expected original Stage61 local QA screen, not independent preview")

    main = (project/MAIN).read_text()
    screen = (project/SOURCE).read_text()
    if (main.count("DedaWeeklyAccountViewGate(") != 2 or
        main.count("DedaWeeklyLeaderboardSafeScreen(") != 2 or
        main.count("currentAccountStillAuthorized: stillSameViewer") != 2 or
        main.count("onOpenDailyTasks: () {") != 2 or
        "DedaWeeklyOriginalPublicProfileViewer" in main or
        screen.count("privateQaAccountScope:") != 1 or
        "onOpenExistingPublicProfile:" in screen or
        "DedaWeeklyOriginalPublicProfileViewer" in screen):
        raise ValueError("Unexpected original stage61 route or screen")
    bridge = (ROOT/ADDITION).read_text()
    if any(needle not in bridge for needle in (
        "DedaSocialService.findByPublicId",
        "competitor.originalPublicId",
        "currentAuthUid() != uid",
        "stillSameViewer()",
        "found.ownerUid == uid",
    )) or any(marker in bridge for marker in (
        "sendFriendRequest(", "FieldValue.increment(", "setState(() => paid",
        "FirebaseFirestore.instance", "grantDiamonds(", "SharedPreferences",
    )):
        raise ValueError("Read-only original profile authority guard missing")
    # New screen must retain all old local QA data, but switch to the
    # ALREADY TESTED safe-screen callback handlers from the source branch.
    upstream = (ROOT/SOURCE).read_text()
    original_start = upstream.index("  /// A tap is authorized against")
    original_end = upstream.index("  @override\n  void dispose()", original_start)
    safe_actions = upstream[original_start:original_end]
    if "_isCurrentVerifiedCompetitor" not in safe_actions or \
       "await widget.onSendExistingFriendRequest?.call(person)" not in safe_actions:
        raise ValueError("Unsafe or missing validated callback source")
    screen = once(screen,
        "import 'deda_weekly_snapshot_decode.dart';",
        "import 'deda_weekly_snapshot_decode.dart';\n"
        "import 'deda_weekly_competitor_public_card.dart';",
        "screen import")
    screen = once(screen,
        "    this.onOpenDailyTasks,",
        "    this.onOpenDailyTasks,\n"
        "    this.onOpenExistingPublicProfile,\n"
        "    this.onSendExistingFriendRequest,\n"
        "    this.friendRelationFor,\n"
        "    this.drawOriginalEquippedAvatar,",
        "screen constructor")
    screen = once(screen,
        "  final VoidCallback? onOpenDailyTasks;",
        """  final VoidCallback? onOpenDailyTasks;

  /// Only ORIGINAL DEDA authenticated read-only social navigation is wired.
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onOpenExistingPublicProfile;
  final Future<void> Function(DedaWeeklyPublicCompetitor)?
      onSendExistingFriendRequest;
  final DedaWeeklyFriendRelation Function(DedaWeeklyPublicCompetitor)?
      friendRelationFor;
  final Widget Function(BuildContext,int,int,double)?
      drawOriginalEquippedAvatar;""",
        "screen callback types")
    screen = once(screen, "  @override\n  void dispose() {",
        safe_actions+"  @override\n  void dispose() {",
        "screen verified callback check")
    target = upstream[upstream.index("      onOpenExistingPublicProfile:",
                                   upstream.index("    return DedaWeeklyLeaderboardPage(")):
                      upstream.index("      current: safeSnapshot?.current",
                                     upstream.index("    return DedaWeeklyLeaderboardPage("))]
    if "drawOriginalEquippedAvatar" not in target or \
       "_requestVerifiedFriend" not in target:
        raise ValueError("Missing source-verified social widget adapter")
    screen = once(screen,
        "    return DedaWeeklyLeaderboardPage(\n      onOpenDailyTasks: widget.onOpenDailyTasks,",
        "    return DedaWeeklyLeaderboardPage(\n"
        "      onOpenDailyTasks: _stillCurrent && widget.onOpenDailyTasks != null\n"
        "          ? () { if (_stillCurrent) widget.onOpenDailyTasks?.call(); }\n"
        "          : null,\n" + target,
        "screen page social forwarding")
    # Side-effect free profile navigation; friendship remains DISABLED.
    # Both original home routes must carry the SAME session/UID guard.
    route_tail = """            },
          ),
      )"""
    profile_callbacks = """            },
            onOpenExistingPublicProfile: (person) =>
                DedaWeeklyOriginalPublicProfileViewer.open(
                  context: leagueContext,
                  competitor: person,
                  stillSameViewer: stillSameViewer,
                  currentAuthUid: () => FirebaseAuth.instance.currentUser?.uid,
                  authEvents: FirebaseAuth.instance.authStateChanges(),
                  drawOriginalEquippedAvatar: (ctx, avatar, frame, size) =>
                      DedaFramedAvatar(
                        avatarStyle: avatar, frameStyle: frame, size: size),
                ),
            drawOriginalEquippedAvatar: (ctx, avatar, frame, size) =>
                DedaFramedAvatar(
                  avatarStyle: avatar, frameStyle: frame, size: size),
          ),
      )"""
    if main.count(route_tail) != 2:
        raise ValueError("Expected two identical original tasks + league route tails")
    main = main.replace(route_tail, profile_callbacks)
    main = once(main,
        "import 'deda_weekly_account_view_gate.dart';",
        "import 'deda_weekly_account_view_gate.dart';\n"
        "import 'deda_weekly_original_public_profile_readonly.dart';",
        "official app import")
    if (main.count("DedaWeeklyOriginalPublicProfileViewer.open(") != 2 or
        main.count("onOpenExistingPublicProfile: (person)") != 2 or
        main.count("DedaFramedAvatar(") < 2 or
        "onSendExistingFriendRequest:" in main or
        main.count("DedaWeeklyAccountViewGate(") != 2 or
        main.count("DedaWeeklyLeaderboardSafeScreen(") != 2 or
        main.count("currentAccountStillAuthorized: stillSameViewer") != 2):
        raise ValueError("Actual original home integration incomplete")
    # Verify every predecessor hash immediately before writes.
    if sha(project/MAIN) != old_hashes[MAIN] or \
       sha(project/SOURCE) != old_hashes[SOURCE]:
        raise ValueError("Concurrent source modification detected")
    (project/MAIN).write_text(main)
    (project/SOURCE).write_text(screen)
    shutil.copy2(ROOT/ADDITION, project/ADDITION)
    changed = {path for path, prior in old_hashes.items()
               if sha(project/path) != prior}
    if changed != {MAIN, SOURCE}:
        raise ValueError("Unexpected original source mutation "+repr(changed))
    for protected in (
        "lib/traffic_quiz_page.dart", "lib/deda_social_service.dart",
        "lib/deda_backend.dart", "lib/deda_pin_auth.dart", "lib/admin_pages.dart",
        "pubspec.yaml", "pubspec.lock",
    ):
        if sha(project/protected) != old_hashes[protected]:
            raise ValueError("Protected original changed: "+protected)
    meta["sourceHashes"] = {
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))
    }
    meta["sourceHashes"].update({
        p:sha(project/p) for p in ("pubspec.yaml","pubspec.lock")
    })
    meta["weeklyOriginalReadOnlyProfile"] = {
        "originalRoutes": 2,
        "readOnlySocialDirectory": True,
        "recheckViewerAfterAsync": True,
        "canonicalOriginalIdOnly": True,
        "recheckAuthUid": True,
        "noFriendshipWrites": True,
        "realVerifiedLeaderboardConnected": False,
        "productionPayoutEnabled": False,
        "realXpWriterChanged": False,
        "quizChanged": False,
        "apkBuilt": False,
    }
    meta["purpose"] = ("ORIGINAL SOURCE ONLY: VERIFIED SOCIAL PUBLIC PROFILE "
                       "READ-ONLY NAVIGATION; NO LIVE LEAGUE OR APK")
    record.write_text(json.dumps(meta,indent=2,ensure_ascii=False)+"\n")
    return meta["weeklyOriginalReadOnlyProfile"]

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project",type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
