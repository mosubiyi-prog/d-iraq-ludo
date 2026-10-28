"""STAGE61 — wire EXISTING original DEDA two-route weekly UI to the
CURRENT account-display scope, without fake rankings or wallet writes.

Apply ONLY to a prepared, SHA-verified, TEMP Stage28 original 100396 candidate.
Never patch repository main.dart, build an APK, publish Rules/Functions/Play.
Works with Stage13+14+16+17+18+19+27+28 verified source chain.

This is local account-specific PRESENTATION protection ONLY, not production
PIN/Auth/AppCheck/XP/server leaderboard verification or migration.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
META = "internal-build-inputs.json"
ACCOUNT_UI = "lib/deda_weekly_account_view_gate.dart"
PACKAGE = "com.diraq.ludo.d_iraq_ludo"
EXPECTED_VERSION = 100396

OLD_ROUTE = (
    "DedaWeeklyLeaderboardSafeScreen(\n"
    "        localTrialAccountKey: DedaBackend.accountKeyForPhone(\n"
    "            DedaPreferences.phone).trim(),\n"
    "        refreshSignal: DedaSocialProgressWallet.xpNotifier,\n"
    "        onOpenDailyTasks: () => Navigator.of(context).push(\n"
    "          MaterialPageRoute<void>(\n"
    "            builder: (_) => const DedaDailyTasksPage(),\n"
    "          ),\n"
    "        ),\n"
    "      )"
)

NEW_ROUTE = (
    "DedaWeeklyAccountViewGate(\n"
    "        readCanonicalAccount: () => DedaBackend.accountKeyForPhone(\n"
    "            DedaPreferences.phone).trim(),\n"
    "        readSessionUid: () {\n"
    "          final user = FirebaseAuth.instance.currentUser;\n"
    "          return user != null && user.isAnonymous ? user.uid : null;\n"
    "        },\n"
    "        authEvents: FirebaseAuth.instance.authStateChanges(),\n"
    "        refreshSignal: DedaSocialProgressWallet.xpNotifier,\n"
    "        builder: (leagueContext, viewerAccount, stillSameViewer) =>\n"
    "          DedaWeeklyLeaderboardSafeScreen(\n"
    "            key: const Key('deda_weekly_scoped_original_screen'),\n"
    "            localTrialAccountKey: viewerAccount,\n"
    "            currentAccountStillAuthorized: stillSameViewer,\n"
    "            refreshSignal: DedaSocialProgressWallet.xpNotifier,\n"
    "            onOpenDailyTasks: () {\n"
    "              if (!stillSameViewer()) return;\n"
    "              Navigator.of(leagueContext).push(\n"
    "                MaterialPageRoute<void>(\n"
    "                  builder: (_) => const DedaDailyTasksPage(),\n"
    "                ),\n"
    "              );\n"
    "            },\n"
    "          ),\n"
    "      )"
)

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise ValueError("STAGE61_SOURCE_ANCHOR_" + label + "_" + str(count))
    return text.replace(old, new, 1)

def bind(project):
    project = Path(project).resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError("Cannot edit original DEDA repo")
    path = project / META
    if not path.is_file():
        raise ValueError("No verified restored original Stage28 candidate")
    data = json.loads(path.read_text())
    if (data.get("package") != PACKAGE or
        data.get("versionCode") != EXPECTED_VERSION or
        data.get("variant") != "candidate" or
        data.get("completeOwnerDelivery") is not False or
        data.get("financialRestoreEnabled") is not False or
        data.get("productionExecutionPerformed") is not False or
        data.get("weeklyStage27", {}).get("adminLeagueTileInOriginal") is not True or
        data.get("weeklyStage28", {}).get("bothOfficialHomeLayouts") is not True or
        data.get("weeklyStage28", {}).get("userXPChanged") is not False or
        data.get("weeklyStage28", {}).get("walletChanged") is not False or
        data.get("weeklyStage17", {}).get("realPrizesCredited") is not False or
        data.get("weeklyStage18", {}).get("writesFirestore") is not False or
        data.get("weeklyStage27", {}).get("actualPrizePayoutEnabled") is not False):
        raise ValueError("Stage61 original app chain not trusted")
    old_hashes = dict(data.get("sourceHashes", {}))
    if not old_hashes or any(
        not (project / p).is_file() or sha(project / p) != digest
        for p, digest in old_hashes.items()
    ):
        raise ValueError("Previous original source hashes changed")
    main = project / "lib/main.dart"
    screen = project / "lib/deda_weekly_leaderboard_safe_screen.dart"
    if (project / ACCOUNT_UI).exists() or not main.is_file() or not screen.is_file():
        raise ValueError("Missing or duplicate protected account scope source")

    m = main.read_text()
    s = screen.read_text()
    # Verify EXACT two original home entries and preserved navigation.
    if (m.count(OLD_ROUTE) != 2 or
        m.count("DedaLeaderboardHomeCard(") != 2 or
        m.count("DedaWeeklyLeaderboardSafeScreen(") != 2 or
        m.count("localTrialAccountKey: DedaBackend.accountKeyForPhone(") != 2 or
        "categoryCard(restaurant)" in m or
        "DedaWeeklyAccountViewGate(" in m or
        "deda_weekly_account_view_gate.dart" in m or
        "loadVerifiedStandings:" in m):
        raise ValueError("Original Stage28 weekly home/account source drift")
    if (s.count("final points=await DedaWeeklyPrivateTrialLocalXp.read(scope);") != 1 or
        s.count("if(scope==null || scope.isEmpty)") != 1 or
        s.count("if(!mounted || widget.localTrialAccountKey!=scope) return;") != 1 or
        "privateQaAccountScope: widget.localTrialAccountKey" not in s or
        "privateTrialXp: _privateTrialScope" not in s or
        s.count("currentAccountStillAuthorized") < 2):
        raise ValueError("Original Stage17 private trial UI source changed")
    addition = (REPO / ACCOUNT_UI).read_text()
    for invariant in [
        "class DedaWeeklyAccountViewGate",
        "_capturedAccount", "_capturedUid",
        "_revoked = true", "authEvents.listen",
        "readSessionUid", "readCanonicalAccount",
    ]:
        if invariant not in addition:
            raise ValueError("Missing stage61 viewer isolation invariant " + invariant)
    for forbidden in [
        "FirebaseFirestore", "SharedPreferences", "grantDiamonds",
        "setState(() => verified", "FieldValue.increment", ".set(", ".update(",
    ]:
        if forbidden in addition:
            raise ValueError("View guard must not write account, score or wallet")

    main_next = once(m,
        "import 'deda_weekly_leaderboard_safe_screen.dart';",
        "import 'deda_weekly_leaderboard_safe_screen.dart';\n"
        "import 'deda_weekly_account_view_gate.dart';",
        "weekly import")
    if "import 'package:firebase_auth/firebase_auth.dart';" not in main_next:
        main_next = once(main_next,
            "import 'package:firebase_core/firebase_core.dart';",
            "import 'package:firebase_core/firebase_core.dart';\n"
            "import 'package:firebase_auth/firebase_auth.dart';",
            "actual Firebase Auth import")
    main_next = main_next.replace(OLD_ROUTE, NEW_ROUTE)
    if (main_next.count(NEW_ROUTE) != 2 or
        main_next.count("DedaWeeklyAccountViewGate(") != 2 or
        main_next.count("DedaLeaderboardHomeCard(") != 2 or
        main_next.count("DedaWeeklyLeaderboardSafeScreen(") != 2 or
        main_next.count("authEvents: FirebaseAuth.instance.authStateChanges(),") != 2 or
        main_next.count("onOpenDailyTasks: () {") < 2 or
        OLD_ROUTE in main_next):
        raise ValueError("Both real original league entries not fully scoped")

    # Original QA own-account XP reader also must never show previous account
    # task XP after a fresh login/session change while read was in flight.
    screen_next = once(s,
        "if(scope==null || scope.isEmpty) {",
        "if(scope==null || scope.isEmpty ||\n"
        "        widget.currentAccountStillAuthorized?.call() != true) {",
        "before private trial read")
    screen_next = once(screen_next,
        "if(!mounted || widget.localTrialAccountKey!=scope) return;",
        "if(!mounted || widget.localTrialAccountKey!=scope ||\n"
        "       widget.currentAccountStillAuthorized?.call() != true) return;",
        "after async trial read")
    screen_next = once(screen_next,
        "      privateQaAccountScope: widget.localTrialAccountKey,",
        "      privateQaAccountScope:\n"
        "          widget.currentAccountStillAuthorized?.call() == true\n"
        "              ? widget.localTrialAccountKey : null,",
        "QA lab access")
    screen_next = once(screen_next,
        "      privateTrialXp: _privateTrialScope == widget.localTrialAccountKey",
        "      privateTrialXp: widget.currentAccountStillAuthorized?.call() == true &&\n"
        "          _privateTrialScope == widget.localTrialAccountKey",
        "private XP footer account guard")
    # No changes yet — validate source diffs and existing SHA before writes.
    if sha(main) != old_hashes["lib/main.dart"] or \
            sha(screen) != old_hashes["lib/deda_weekly_leaderboard_safe_screen.dart"]:
        raise ValueError("Concurrent original source edit detected")
    main.write_text(main_next)
    screen.write_text(screen_next)
    shutil.copy2(REPO / ACCOUNT_UI, project / ACCOUNT_UI)
    changes = {p for p, prior in old_hashes.items()
               if sha(project / p) != prior}
    if changes != {"lib/main.dart",
                   "lib/deda_weekly_leaderboard_safe_screen.dart"}:
        raise ValueError("Protected original files changed: " + repr(changes))
    for locked in [
        "lib/traffic_quiz_page.dart", "lib/deda_backend.dart",
        "lib/admin_pages.dart", "lib/deda_social_service.dart",
        "pubspec.yaml", "pubspec.lock",
    ]:
        if sha(project / locked) != old_hashes[locked]:
            raise ValueError("Stage61 refuses modified quiz, user data, admin, wallet " + locked)

    data["sourceHashes"] = {
        str(p.relative_to(project)): sha(p)
        for p in sorted((project / "lib").rglob("*.dart"))
    }
    data["sourceHashes"].update({
        p: sha(project / p) for p in ["pubspec.yaml", "pubspec.lock"]
    })
    # IMPORTANT: no APK is built; version number reserved from Stage28 only.
    data["weeklyStage61"] = {
        "officialHomeRoutesScoped": 2,
        "originalAnonymousUidAndAccountCaptured": True,
        "reactiveAuthSignOutInvalidation": True,
        "reactiveXpAccountSwitchCheck": True,
        "localQaXpScopedToCapturedViewer": True,
        "verifiedGlobalRankingsAvailable": False,
        "actualWeeklyPrizePayoutEnabled": False,
        "realCrossDeviceAccountMigrationEnabled": False,
        "serverAccountBindingProofProvided": False,
        "walletOrXpChanged": False,
        "quizBankChanged": False,
        "firebaseRulesOrProductionFunctionsChanged": False,
        "apkBuilt": False,
        "privateQaSourceOnly": True,
    }
    data["purpose"] = (
        "STAGE61 ORIGINAL TWO-HOME ACCOUNT-SCOPED LEAGUE UI SOURCE QA; "
        "SERVER RANKINGS, PAYOUTS, PRODUCTION AUTH AND APK NOT ENABLED"
    )
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return data["weeklyStage61"]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    print(json.dumps(bind(parser.parse_args().project), ensure_ascii=False))
