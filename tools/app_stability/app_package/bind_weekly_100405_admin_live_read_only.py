"""100405 QA stage 1 of 5; real GM ranking and closed-week history only.

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
    model.write_text(page)
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
        'managerPauseFreezeSourceCreated':True,
        'managerPauseFreezeFirestoreRulesTestPending':True,
    }
    file.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    return meta['weekly100405AdminProgress']

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('workspace',type=Path)
    print(json.dumps(bind(parser.parse_args().workspace),ensure_ascii=False))
