"""DEDA 100392 private local XP trial on the actual original 100391 app.

Shows only OWN account's matched REAL locally persisted claimed-task+20XP
records in the existing leaderboard footer. DOES NOT mark them server-verified
and does NOT populate the global top ten or issue any diamonds.
Code changes happen only in temporary Flutter build root, never repo main.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
ADDITION='lib/deda_weekly_private_trial_local_xp.dart'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def one(s,a,b,label):
    if s.count(a)!=1:raise ValueError('Stage17 anchor not unique: '+label)
    return s.replace(a,b,1)

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('Never patch repository original')
    manifest=project/'internal-build-inputs.json'
    data=json.loads(manifest.read_text())
    if (data.get('versionCode')!=100391 or
        data.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        data.get('completeOwnerDelivery') is not False or
        data.get('activeIdStage16',{}).get('measuredStartupActive') is not True or
        data.get('financialRestoreEnabled') is not False or
        (project/ADDITION).exists() or
        any(not (project/p).is_file() or sha(project/p)!=h
            for p,h in data['sourceHashes'].items())):
        raise ValueError('Expected pristine ORIGINAL signed 100391 candidate')
    main=project/'lib/main.dart'
    screen=project/'lib/deda_weekly_leaderboard_safe_screen.dart'
    page=project/'lib/deda_weekly_leaderboard_page.dart'
    s=main.read_text()
    s=one(s,"const DedaWeeklyLeaderboardSafeScreen()",
        """DedaWeeklyLeaderboardSafeScreen(
        localTrialAccountKey: DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
      )""","first home tile")
    # The second layout now has just one untouched const route.
    s=s.replace("const DedaWeeklyLeaderboardSafeScreen()",
        """DedaWeeklyLeaderboardSafeScreen(
        localTrialAccountKey: DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
      )""",1)
    if s.count('localTrialAccountKey:')!=2 or \
       'const DedaWeeklyLeaderboardSafeScreen()' in s:
        raise ValueError('Must activate EXACTLY TWO private trial routes')
    main.write_text(s)

    t=screen.read_text()
    t=one(t,"import 'deda_weekly_snapshot_decode.dart';",
        "import 'deda_weekly_snapshot_decode.dart';\n"
        "import 'deda_weekly_private_trial_local_xp.dart';",'trial import')
    t=one(t,"    this.refreshInterval,\n  });",
        "    this.refreshInterval,\n    this.localTrialAccountKey,\n  });",
        'optional original screen constructor')
    t=one(t,"  final Duration? refreshInterval;",
        "  final Duration? refreshInterval;\n"
        "  /// Original account number for LOCAL QA only. Never a winner ID.\n"
        "  final String? localTrialAccountKey;",'account field')
    t=one(t,"  bool _requestInFlight = false;",
        "  bool _requestInFlight = false;\n"
        "  int? _privateTrialXp;\n"
        "  String? _privateTrialScope;",'private state')
    t=one(t,"    _attach();\n  }\n\n  void _attach() {",
        "    _attach();\n    unawaited(_readPrivateTrial());\n  }\n\n"
        """  Future<void> _readPrivateTrial() async {
    final scope=widget.localTrialAccountKey;
    if(scope==null || scope.isEmpty) {
      if(mounted) setState(()=>_privateTrialXp=null);
      return;
    }
    final points=await DedaWeeklyPrivateTrialLocalXp.read(scope);
    if(!mounted || widget.localTrialAccountKey!=scope) return;
    setState(() {
      _privateTrialScope=scope;
      _privateTrialXp=points;
    });
  }

  void _attach() {""",'trial local read method')
    t=one(t,"  void _onRefreshSignal() {\n    if (_hasVerifiedReader)",
        "  void _onRefreshSignal() {\n    unawaited(_readPrivateTrial());\n    if (_hasVerifiedReader)",
        'refresh after actual +20 XP')
    t=one(t,"    if (state == AppLifecycleState.resumed && _hasVerifiedReader) {",
        """    if (state == AppLifecycleState.resumed) {
      unawaited(_readPrivateTrial());
    }
    if (state == AppLifecycleState.resumed && _hasVerifiedReader) {""",
        'midnight resume refresh')
    t=one(t,"        oldWidget.refreshInterval != widget.refreshInterval) {",
        "        oldWidget.refreshInterval != widget.refreshInterval ||\n"
        "        oldWidget.localTrialAccountKey != widget.localTrialAccountKey) {",
        'on account scope change')
    t=one(t,"      setState(() => _snapshot = null);\n      _attach();",
        "      setState(() { _snapshot = null; _privateTrialXp=null; });\n"
        "      _attach();\n      unawaited(_readPrivateTrial());",
        'clear account previous')
    t=one(t,"      previous: safeSnapshot?.previous ??",
        "      privateTrialXp: _privateTrialScope == widget.localTrialAccountKey\n"
        "          ? _privateTrialXp : null,\n"
        "      previous: safeSnapshot?.previous ??",
        'pass trial to footer')
    screen.write_text(t)

    p=page.read_text()
    p=one(p,"    this.previewOnly = false,",
        "    this.previewOnly = false,\n    this.privateTrialXp,",
        'new footer option')
    p=one(p,"  final bool previewOnly;",
        "  final bool previewOnly;\n"
        "  /// Non-authoritative own-phone diagnostic only, never global ranking.\n"
        "  final int? privateTrialXp;",'trial amount')
    p=one(p,"                          : 'الترتيب قيد التحقق من الخادم؛ '\n"
        "                            'لن تُعرض نتائج وهمية أو تُصرف جوائز.',",
        """                          : widget.privateTrialXp != null
                          ? 'فحص نقاط مهامي هذا الأسبوع: '
                            '@@{widget.privateTrialXp} XP محلياً؛ '
                            'لا ترتيب حقيقياً ولا جوائز.'
                          : 'الترتيب قيد التحقق من الخادم؛ '
                            'لن تُعرض نتائج وهمية أو تُصرف جوائز.',""".replace('@@','$'),
        'footer private XP notice')
    page.write_text(p)
    shutil.copy2(ROOT/ADDITION,project/ADDITION)
    modifications={rel for rel,old in data['sourceHashes'].items()
                   if sha(project/rel)!=old}
    expected={'lib/main.dart','lib/deda_weekly_leaderboard_safe_screen.dart',
              'lib/deda_weekly_leaderboard_page.dart'}
    if modifications!=expected:raise ValueError('Unexpected changed files '+repr(modifications))
    data['sourceHashes']={str(p.relative_to(project)):sha(p) for p in
                          (project/'lib').rglob('*.dart')}
    data['sourceHashes'].update({
        p:sha(project/p) for p in ('pubspec.yaml','pubspec.lock')})
    data['versionCode']=100392
    data['weeklyStage17']={
      'privateQa':True,'ownAccountLocalTrialXp':True,
      'midnightRefreshOnResume':True,'taskAndXpDualReceiptRequired':True,
      'noForgedGlobalRanks':True,'serverIssuedResults':False,
      'verifiedProductionWeeklyLeague':False,'realPrizesCredited':False,
      'originalWalletXpUnchanged':True,
      'provisionalTrialWeekStart':'Monday 00:00 Iraq',
    }
    data['purpose']='ORIGINAL 100392 private TASK midnight trial, NO REAL LEAGUE'
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    return data['weeklyStage17']

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('project',type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
