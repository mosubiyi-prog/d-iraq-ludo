"""DEDA 100404: keep same full leaderboards, put clock where old prev week tab was.

Exactly 100403 -> 100404 isolated private build. No source/Play/wallet changes.
"""
from pathlib import Path
import json,hashlib,shutil,argparse

ROOT=Path(__file__).resolve().parents[3]
MAIN='lib/main.dart'
PAGE='lib/deda_weekly_leaderboard_page.dart'
CLOCK='lib/deda_weekly_league_clock.dart'
DIRECT='lib/deda_weekly_firestore_direct_bridge.dart'
OUTBOX='lib/deda_weekly_community_outbox.dart'

HEADER_ROW="""        Expanded(
          flex: 5,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: gold,
                    border: Border.all(color: gold),
                    borderRadius: BorderRadius.circular(28 * scale),
                  ),
                  child: fitted('الأسبوع الحالي',
                      size: 13 * scale, color: navy),
                ),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                flex: 5,
                child: Container(
                  key: const Key('deda-weekly-inline-countdown'),
                  alignment: Alignment.center,
                  decoration: panel(blue, radius: 13 * scale),
                  padding: EdgeInsets.symmetric(horizontal: 3 * scale),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      fitted(clock.heading, size: 11 * scale, color: silver),
                      fitted(clock.countdown,
                          size: 17 * scale, color: gold, ltr: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

"""

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bind(project):
    p=Path(project).resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents:
        raise ValueError('original user project must not be modified')
    manifest=p/'internal-build-inputs.json'
    m=json.loads(manifest.read_text())
    if (m.get('versionCode')!=100403 or
        m.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        m.get('variant')!='candidate' or
        m.get('financialRestoreEnabled') is not False or
        m.get('productionExecutionPerformed') is not False or
        m.get('weekly100403FirstOpenGate',{}).get('officialHomeRoutes')!=2 or
        m.get('weekly100402FirestoreDirect',{}).get('noWalletOrDiamondWrites') is not True):
        raise ValueError('version 100403 SHA verified reference only')
    for name,h in m['sourceHashes'].items():
        f=p/name
        if not f.exists() or sha(f)!=h:
            raise ValueError('SOURCE_SHA_MISMATCH '+name)
    main=(p/MAIN).read_text()
    startAt="        startsAt: DateTime.utc(2026, 10, 31, 3),\n"
    if main.count(startAt)!=2:
        raise ValueError('the two original leaderboard routes are not confirmed')
    # Keep the account gate but never replace the leaderboard with blank screen.
    main=main.replace(startAt,'')
    (p/MAIN).write_text(main)

    src=(p/PAGE).read_text()
    if src.count("  Widget header(double scale) {")!=1 or \
       src.count("  /// Status is the same for portrait and landscape")!=1 or \
       src.count("'الأسبوع السابق'")!=1:
        raise ValueError('original owner-approved league layout changed')
    src=src.replace(
        "import 'dart:math' as math;",
        "import 'dart:async';\nimport 'dart:math' as math;\nimport 'deda_weekly_league_clock.dart';",1)
    src=src.replace("    this.previewOnly = false,",
        "    this.previewOnly = false,\n    this.clock,",1)
    src=src.replace("  final bool previewOnly;",
        "  final bool previewOnly;\n  final DateTime Function()? clock;",1)
    src=src.replace("  bool previousWeek = false;",
"""  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (!widget.previewOnly) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
""",1)
    src=src.replace("DedaLeaderboardViewData get view =>\n      previousWeek ? widget.previous : widget.current;",
                    "DedaLeaderboardViewData get view => widget.current;",1)
    header_start=src.index("  Widget header(double scale) {")
    header_end=src.index("  /// Status is the same for portrait and landscape",header_start)
    header=src[header_start:header_end]
    old_time="""    final remaining = view.remainingUntilWeekEnd;
    String timeLabel = 'بانتظار وقت الأسبوع';
    if (view.verified && remaining != null) {
      final safe = remaining.isNegative ? Duration.zero : remaining;
      timeLabel =
          '${safe.inDays} يوم ${safe.inHours.remainder(24)} س';
    }
"""
    # The preceding string is the exact original source text; dollar signs
    # in the committed source remain Dart interpolation, not Python formatting.
    old_time=old_time.replace('\\$','$')
    if header.count(old_time)!=1:
        raise ValueError('clock helper cannot replace owner-approved timer')
    header=header.replace(old_time,
      "    final clock = DedaWeeklyLeagueClock.at(widget.clock?.call() ?? DateTime.now());\n",1)
    rowstart=header.index("        Expanded(\n          flex: 5,\n          child: Row(\n            children: [")
    header=header[:rowstart]+HEADER_ROW
    src=src[:header_start]+header+src[header_end:]
    trial="widget.privateTrialXp != null && !previousWeek && !view.verified"
    if src.count(trial)!=1:
        raise ValueError('expected current 100403 local-QA footer')
    src=src.replace(trial,"widget.privateTrialXp != null && !view.verified",1)
    anchor="            : view.verified\n"
    if src.count(anchor)!=1:
        raise ValueError('original 100403 status footer changed')
    src=src.replace(anchor,
"""            : DedaWeeklyLeagueClock.at(
                widget.clock?.call() ?? DateTime.now()).phase ==
                DedaWeeklyPhase.beforeFirstWeek
                ? 'الدوري يبدأ الساعة 6 صباحاً؛ لا نقاط أسبوعية قبل البداية.'
            : DedaWeeklyLeagueClock.at(
                widget.clock?.call() ?? DateTime.now()).phase ==
                DedaWeeklyPhase.frozen
                ? 'تجميد الدوري: المراكز والنقاط ثابتة حتى 6 صباحاً.'
            : view.verified
""",1)
    if "'الأسبوع السابق'" in src or 'previousWeek' in src:
        raise ValueError('previous week UI was not fully removed')
    if src.count('DedaWeeklyLeaderboardPage')<1 or \
       src.count('podiumRow(scale)')!=2 or \
       src.count('rankingTable(scale)')!=2 or \
       src.count("deda-weekly-inline-countdown")!=1:
        raise ValueError('original podium/rank layout changed')
    (p/PAGE).write_text(src)

    shutil.copy2(ROOT/CLOCK,p/CLOCK)
    # Direct league scoring module already includes explicit BEFORE-6am and
    # FROZEN guards. Copy only this module, never original DEDA task engine.
    originalDirect=(p/DIRECT).read_text()
    updatedDirect=(ROOT/DIRECT).read_text()
    if (originalDirect.count('static Future<bool> _send(')!=1 or
        updatedDirect.count('DedaWeeklyLeagueClock.at(')!=2):
        raise ValueError('unexpected direct Firestore score module')
    (p/DIRECT).write_text(updatedDirect)
    originalOutbox=(p/OUTBOX).read_text()
    newestOutbox=(ROOT/OUTBOX).read_text()
    if (not any(marker in originalOutbox for marker in (
          "static const _prefix = 'deda_weekly_community_pending_100400';",
          "static const _prefix = 'deda_weekly_community_pending_100404';"
        )) or
        "static const _prefix = 'deda_weekly_community_pending_100404';" not in newestOutbox):
        raise ValueError('Cannot safely isolate pre-six legacy pending reports')
    (p/OUTBOX).write_text(newestOutbox)
    for relative in (MAIN,PAGE,CLOCK,DIRECT,OUTBOX):
        m['sourceHashes'][relative]=sha(p/relative)
    m['versionCode']=100404
    m['weekly100404InlineClock']={
        'weekStartsSaturday06Baghdad':True,
        'freezesSaturday00Through06':True,
        'beforeFirstStartNoQueueOrScore':True,
        'oldPreStartReportsCannotReplayAfterStart':True,
        'fullLeaderboardAlwaysVisible':True,
        'previousWeekTabRemoved':True,
        'inlineCountdownInOriginalTopRow':True,
        'previousProductionRulesUntouched':True,
        'originalXpOrDiamondsChanged':False,
        'bothOfficialHomeRoutes':2,
    }
    manifest.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
    return m['weekly100404InlineClock']

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('project',type=Path)
    print(json.dumps(bind(ap.parse_args().project),ensure_ascii=False))
