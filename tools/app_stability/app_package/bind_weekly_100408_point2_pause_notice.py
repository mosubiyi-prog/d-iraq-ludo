"""DEDA 100408 point 2: show realtime GM maintenance pause in bottom league info card.

After point1 in isolated candidate. Uses existing signed-in Firestore GET rule.
Never exposes private audit reason, never modifies scoring, identity or awards.
"""
from pathlib import Path
import json,hashlib,argparse
ROOT=Path(__file__).resolve().parents[3]
SAFE="lib/deda_weekly_leaderboard_safe_screen.dart"
PAGE="lib/deda_weekly_leaderboard_page.dart"

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def once(s,a,b,label):
    if s.count(a)!=1:raise ValueError("100408 p2 drift "+label)
    return s.replace(a,b,1)
def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("source checkout is protected")
    manifest=project/"internal-build-inputs.json"
    m=json.loads(manifest.read_text())
    if (m.get("versionCode")!=100408 or
        m.get("weekly100408Point1",{}).get("verifiedServerOwnedActiveAndColorOnePass") is not True):
        raise ValueError("point1 verified build must precede point2")
    for p,h in m["sourceHashes"].items():
        if not (project/p).is_file() or sha(project/p)!=h:
            raise ValueError("p2 baseline SHA drift "+p)
    page=(project/PAGE).read_text()
    page=once(page,"    this.reviewNotice,\n","    this.reviewNotice,\n    this.maintenanceNotice,\n","constructor")
    page=once(page,"  final String? reviewNotice;\n",
        "  final String? reviewNotice;\n"
        "  /// Server-read current week GM pause; never inferred from the phone.\n"
        "  final String? maintenanceNotice;\n","field")
    page=once(page,
        "child: fitted(view.reviewNotice != null\n",
        "child: fitted(widget.maintenanceNotice != null\n"
        "            ? widget.maintenanceNotice!\n"
        "            : view.reviewNotice != null\n",
        "fixed bottom explainer panel priority")
    (project/PAGE).write_text(page)
    safe=(project/SAFE).read_text()
    safe=once(safe,"import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\n"
        "import 'package:firebase_auth/firebase_auth.dart';\n"
        "import 'package:cloud_firestore/cloud_firestore.dart';\n"
        "import 'deda_weekly_league_clock.dart';",
        "public status imports")
    safe=once(safe,"    return DedaWeeklyLeaderboardPage(",
        """    // Public neutral status only. It is impossible for an unsigned
    // client-side phrase to pause the league: Firestore Rules own that.
    if (!_stillCurrent || FirebaseAuth.instance.currentUser?.uid == null) {
      return DedaWeeklyLeaderboardPage(
        onOpenDailyTasks: widget.onOpenDailyTasks,
        current: const DedaLeaderboardViewData(
          verified: false, rows: [], profilesByUid: {}),
      );
    }
    final localWeek = DedaWeeklyLeagueClock.at(
      DateTime.now().toUtc()).weekStart.add(const Duration(hours: 3));
    final weekId = '${localWeek.year.toString().padLeft(4, '0')}-'
        '${localWeek.month.toString().padLeft(2, '0')}-'
        '${localWeek.day.toString().padLeft(2, '0')}';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(
        'deda_weekly_direct_control').doc('active').snapshots(),
      builder: (context, controlSnapshot) {
        final state = controlSnapshot.data?.data();
        final isPaused = controlSnapshot.hasData &&
            !controlSnapshot.hasError &&
            state?['weekId'] == weekId && state?['paused'] == true;
        final reason = state?['reason'] is String
            ? (state!['reason'] as String).toLowerCase() : '';
        final maintenance = isPaused &&
            (reason.contains('صيانة') || reason.contains('maintenance'));
        final pauseNotice = !isPaused ? null : maintenance
            ? '🛠️ الدوري تحت الصيانة مؤقتاً؛ المدة المتوقعة 30 إلى 90 دقيقة. '
              'نقاط المستوى والماسات محفوظة.'
            : '⏸️ الدوري متوقف مؤقتاً من الإدارة؛ '
              'نقاط المستوى والماسات محفوظة.';
        return DedaWeeklyLeaderboardPage(
          maintenanceNotice: pauseNotice,""",
        "verified paused state wrapper")
    end_marker="    );\n  }\n}\n"
    if not safe.endswith(end_marker):
        raise ValueError("p2 safe screen end drift")
    safe=safe[:-len(end_marker)]+"    );\n      },\n    );\n  }\n}\n"
    assert safe.count("maintenanceNotice: pauseNotice")==1
    (project/SAFE).write_text(safe)
    for p in (PAGE,SAFE):m["sourceHashes"][p]=sha(project/p)
    m["weekly100408Point2"]={
        "readsCurrentWeekPauseInRealtime":True,
        "bottomFixedPanelNoScroll":True,
        "estimatedMaintenanceMinutes30To90":True,
        "genericPauseDoesNotMislabelMaintenance":True,
        "clearsOnResume":True,
        "sameAccountAuthenticatedGate":True,
        "doesNotChangeXPOrWallet":True,
    }
    manifest.write_text(json.dumps(m,ensure_ascii=False,indent=2)+"\n")
    return m["weekly100408Point2"]
if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("workspace",type=Path)
    print(json.dumps(bind(p.parse_args().workspace),ensure_ascii=False))
