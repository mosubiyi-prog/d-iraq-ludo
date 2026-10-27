"""Attach a clearly marked FUNCTIONAL OWNER QA dialog to original DEDA 100393.
After Stage13+14+16+17 private candidate only. NO real XP, balance, Firestore
or Play change. The canonical league remains awaiting verified backend.
"""
from pathlib import Path
import hashlib
import json
import shutil
import argparse

ROOT=Path(__file__).resolve().parents[3]
ADD='lib/deda_weekly_qa_full_trial.dart'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def once(text,old,new,label):
    count=text.count(old)
    if count!=1:
        raise ValueError('Stage18 unsafe source match '+label+' '+str(count))
    return text.replace(old,new,1)

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('Never edit original DEDA repository')
    meta=project/'internal-build-inputs.json'
    data=json.loads(meta.read_text())
    if (data.get('versionCode')!=100392 or
        data.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        data.get('financialRestoreEnabled') is not False or
        data.get('completeOwnerDelivery') is not False or
        data.get('weeklyStage17',{}).get('serverIssuedResults') is not False or
        data.get('weeklyStage17',{}).get('realPrizesCredited') is not False or
        not data.get('activeIdStage16',{}).get('measuredStartupActive') or
        (project/ADD).exists() or
        any(not (project/path).is_file() or sha(project/path)!=digest
            for path,digest in data['sourceHashes'].items())):
        raise ValueError('Only untouched 100392 QA candidate is accepted')
    page=project/'lib/deda_weekly_leaderboard_page.dart'
    screen=project/'lib/deda_weekly_leaderboard_safe_screen.dart'
    p=page.read_text()
    s=screen.read_text()
    p=once(p,"import 'deda_weekly_leaderboard_policy.dart';",
      "import 'deda_weekly_leaderboard_policy.dart';\n"
      "import 'deda_weekly_qa_full_trial.dart';",'QA-only import')
    p=once(p,'    this.privateTrialXp,',
      '    this.privateTrialXp,\n    this.privateQaAccountScope,',
      'explicit QA constructor')
    p=once(p,'  final int? privateTrialXp;',
      '  final int? privateTrialXp;\n'
      '  /// Present only in original-package PRIVATE owner QA APK.\n'
      '  final String? privateQaAccountScope;', 'QA account scope')
    p=once(p,
      "                    actions: [\n"
      "                      TextButton(onPressed: () => Navigator.pop(context),",
      """                    actions: [
                      if (widget.privateQaAccountScope != null &&
                          RegExp(r'^\d{10,16}$')
                              .hasMatch(widget.privateQaAccountScope!))
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(this.context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DedaWeeklyQaFullTrialPage(
                                  accountScope: widget.privateQaAccountScope!,
                                  initialLocalXp: widget.privateTrialXp ?? 0,
                                ),
                              ),
                            );
                          },
                          child: const Text('فتح مختبر الدوري'),
                        ),
                      TextButton(onPressed: () => Navigator.pop(context),""",
      'QA link inside info dialog')
    s=once(s,'      privateTrialXp: _privateTrialScope',
      '      privateQaAccountScope: widget.localTrialAccountKey,\n'
      '      privateTrialXp: _privateTrialScope',
      'pass genuine user account scope')
    page.write_text(p)
    screen.write_text(s)
    shutil.copy2(ROOT/ADD,project/ADD)
    changed={path for path,digest in data['sourceHashes'].items()
             if sha(project/path)!=digest}
    allowed={'lib/deda_weekly_leaderboard_page.dart',
             'lib/deda_weekly_leaderboard_safe_screen.dart'}
    if changed!=allowed:
        raise ValueError('Unexpected original source mutation '+repr(changed))
    data['sourceHashes']={
        str(p.relative_to(project)):sha(p)
        for p in (project/'lib').rglob('*.dart')}
    data['sourceHashes'].update({
      'pubspec.yaml':sha(project/'pubspec.yaml'),
      'pubspec.lock':sha(project/'pubspec.lock')})
    data['versionCode']=100393
    data['weeklyStage18']={
      'privateQaOnly':True,'allTenPlacesTestable':True,
      'eleventhNoPrize':True,'currentAndPreviousTestWeeks':True,
      'sandboxDiamondExactlyOnce':True,'canResetOnlySandbox':True,
      'officialLeaderboardStillAwaitingServer':True,
      'writesRealWallet':False,'writesRealXp':False,
      'writesFirestore':False,'fakePlayersInLiveLeaderboard':False,
      'signedOriginalPackage':True,
    }
    data['purpose']='ORIGINAL 100393 INTERACTIVE PRIVATE LEAGUE QA, NO REAL PAYOUT OR PLAY'
    meta.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    return data['weeklyStage18']

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('project',type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
