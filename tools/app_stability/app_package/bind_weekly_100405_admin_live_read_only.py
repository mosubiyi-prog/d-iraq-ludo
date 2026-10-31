"""100405 integrated seven-point owner feature bundle; QA workspace ONLY.

Never create APK or change source source tree, Firestore rules, XP or wallets.
Must start from SHA-checked accepted owner-tested 100404 workspace.
"""
import argparse,hashlib,json,shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MANIFEST='internal-build-inputs.json'
NEW_FILES=[
 'lib/deda_admin_league_live_data.dart',
 'lib/deda_admin_league_live_widgets.dart',
 'lib/deda_admin_league_controls.dart',
 'lib/deda_admin_league_control_widgets.dart',
 'lib/deda_admin_league_reward_status.dart',
]
PAGE='lib/deda_admin_league_page.dart'

def digest(f):return hashlib.sha256(f.read_bytes()).hexdigest()

def bind(project):
    p=Path(project).resolve()
    if p==ROOT or p in ROOT.parents or ROOT in p.parents:
        raise ValueError('NEVER edit source repository/approved package')
    file=p/MANIFEST
    meta=json.loads(file.read_text())
    if (meta.get('versionCode')!=100404 or
        meta.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        meta.get('variant')!='candidate' or
        meta.get('financialRestoreEnabled') is not False or
        meta.get('productionExecutionPerformed') is not False or
        meta.get('weekly100404InlineClock',{}).get('fullLeaderboardAlwaysVisible') is not True):
        raise ValueError('SHA approved original 100404 required')
    for name,h in meta['sourceHashes'].items():
        target=p/name
        if not target.is_file() or digest(target)!=h:
            raise ValueError('BASELINE_HASH_CHANGED '+name)
    # Stage27 already copied the exact source admin page from this branch:
    # update only the new companions, never rewrite the dashboard.
    manager=p/PAGE
    approved=ROOT/PAGE
    if manager.read_bytes()!=approved.read_bytes() or \
       manager.read_text().count('DedaAdminLeagueOverview(')<2 or \
       'liveDataEnabled: true' not in manager.read_text() or \
       'currentAdminProfile(' not in manager.read_text():
        raise ValueError('Approved original GM-only entry changed')
    for name in NEW_FILES:
        target=p/name
        if target.exists():raise ValueError('New admin module already exists')
        shutil.copy2(ROOT/name,target)
        meta['sourceHashes'][name]=digest(target)
    meta['sourceHashes'][PAGE]=digest(manager)
    # Preserve accepted 100404 in source; only in 100405 assembled workspace
    # carry legitimate same-week task receipts across a GM review/stop.
    for source,target in (
        ('lib/deda_weekly_community_outbox_100405.dart',
         'lib/deda_weekly_community_outbox.dart'),
        ('lib/deda_weekly_firestore_direct_bridge_100405.dart',
         'lib/deda_weekly_firestore_direct_bridge.dart'),
    ):
        if not (p/target).is_file() or target not in meta['sourceHashes']:
            raise ValueError('100404 league score source absent: '+target)
        shutil.copy2(ROOT/source,p/target)
        meta['sourceHashes'][target]=digest(p/target)
    # Admin review notification is private to the signed-in DEDA account.
    # Extend ONLY the assembled 100404 UI/decoder, not the accepted source.
    model=p/'lib/deda_weekly_leaderboard_page.dart'
    page=model.read_text()
    constructor='    this.remainingUntilWeekEnd,\n'
    field='  final Duration? remainingUntilWeekEnd;\n'
    status='child: fitted(widget.previewOnly\n'
    if (page.count(constructor)!=1 or page.count(field)!=1 or
        page.count(status)!=1):
        raise ValueError('100404 owner-approved league notice anchors changed')
    page=page.replace(constructor,constructor+'    this.reviewNotice,\n',1)
    page=page.replace(field,field+'  final String? reviewNotice;\n',1)
    page=page.replace(status,
        "child: fitted(view.reviewNotice != null\n"
        "            ? (view.reviewNotice!.contains('اكتملت')\n"
        "                ? 'إشعار الإدارة: تم رفع تجميد نقاط الدوري.'\n"
        "                : 'إشعار الإدارة: نقاط الدوري قيد المراجعة.')\n"
        "            : widget.previewOnly\n",1)
    # Seven-point owner bundle: eliminate the confusing QA sandbox entry
    # from the ACTUAL public league info popup, not its isolated Flutter tests.
    # This only alters the workspace after verifying the 100404 base SHA.
    qa_start = "                      if (widget.privateQaAccountScope != null &&\\n"
    qa_end = "                          child: const Text('فتح مختبر الدوري'),\\n                        ),\\n"
    if page.count(qa_start) != 1 or page.count(qa_end) != 1:
        raise ValueError('Original QA lab entry changed; refuse destructive UI patch')
    left = page.index(qa_start)
    right = page.index(qa_end, left) + len(qa_end)
    if right - left > 1100 or 'DedaWeeklyQaFullTrialPage(' not in page[left:right]:
        raise ValueError('Cannot precisely isolate only the obsolete QA lab button')
    page = page[:left] + page[right:]
    if "فتح مختبر الدوري" in page or 'DedaWeeklyQaFullTrialPage(' in page:
        raise ValueError('User-facing league still exposes QA sandbox')

    # Keep the two-line clock host, its width, the podium geometry and
    # the Saturday 06:00/00:00 time boundaries unchanged.
    old_clock = "                      fitted(clock.countdown,\\n                          size: 17 * scale, color: gold, ltr: true),"
    new_clock = (
        "                      fitted(clock.daysAndHours,\\n"
        "                          size: 15 * scale, color: gold),\\n"
        "                      fitted(clock.minutesAndSeconds,\\n"
        "                          size: 11 * scale, color: silver),"
    )
    if page.count(old_clock) != 1 or page.count("deda-weekly-inline-countdown") != 1:
        raise ValueError('Owner-approved leaderboard countdown slot changed')
    page = page.replace(old_clock, new_clock, 1)
    if "fitted(clock.countdown" in page or 'previousWeek' in page:
        raise ValueError('Old total-hour counter or old week tab still visible')
    model.write_text(page)
    # Original 100404 week math is retained exactly; extra display getters
    # belong ONLY to this 100405 feature bundle, never the rollback 100404.
    clock_module = p/'lib/deda_weekly_league_clock.dart'
    clock_upgrade = ROOT/'lib/deda_weekly_league_clock_100405.dart'
    if clock_module.read_text().count('class DedaWeeklyLeagueClock') != 1 or \\
       clock_module.read_text().count('String get countdown') != 1 or \\
       clock_upgrade.read_text().count('String get daysAndHours') != 1:
        raise ValueError('Could not preserve original authoritative weekly clock')
    shutil.copy2(clock_upgrade, clock_module)
    meta['sourceHashes']['lib/deda_weekly_league_clock.dart'] = digest(clock_module)
    parse=p/'lib/deda_weekly_snapshot_decode.dart'
    decoder=parse.read_text()
    finish='      remainingUntilWeekEnd: Duration(milliseconds: remainingMs),\n'
    rtrn='    return DedaLeaderboardViewData(\n      verified: true,'
    if decoder.count(finish)!=1 or decoder.count(rtrn)!=1:
        raise ValueError('100404 source snapshot contract changed')
    decoder=decoder.replace(rtrn,
        "    final reviewNotice = json['reviewNotice'];\n"
        "    if (reviewNotice != null && (reviewNotice is! String ||\n"
        "        reviewNotice.length < 12 || reviewNotice.length > 240)) {\n"
        "      throw const FormatException('invalid private manager notice');\n"
        "    }\n"
        +rtrn,1)
    decoder=decoder.replace(finish,
        finish+'      reviewNotice: reviewNotice as String?,\n',1)
    parse.write_text(decoder)
    for path in ('lib/deda_weekly_leaderboard_page.dart',
                 'lib/deda_weekly_snapshot_decode.dart'):
        meta['sourceHashes'][path]=digest(p/path)
    meta['versionCode']=100405
    meta['weekly100405AdminProgress']={
        'readOnlyLiveTopTen':True,
        'topThreeFromSameLiveSource':True,
        'priorWeeksFromFrozenFirestoreDocs':True,
        'manualLeagueControlsActive':False,
        'diamondSettlementActive':False,
        'userFreezeNotificationActive':False,
        'approved100404Unchanged':True,
        'apkDelivered':False,
        'stageOfFive':2,
        'privateAdminReviewNoticeInLeague':True,
        'heldTaskSameWeekRetryOnly':True,
        'priorWeekReplayForbidden':True,
        'sevenPointOwnerBundle':True,
        'ownerRemovedPublicQaLabEntry':True,
        'ownerCountDaysHoursMinutesSeconds':True,
        'weekdayOrFreezeBoundariesChanged':False,
        'managerPauseFreezeSourceCreated':True,
        'managerPauseFreezeFirestoreRulesTestPending':True,
    }
    file.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    return meta['weekly100405AdminProgress']

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('workspace',type=Path)
    print(json.dumps(bind(parser.parse_args().workspace),ensure_ascii=False))
