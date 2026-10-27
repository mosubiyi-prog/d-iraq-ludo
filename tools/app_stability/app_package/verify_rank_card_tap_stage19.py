"""Stage19 signed original 100394: verify accessible, clickable rank cards.

Stage18 binds the owner-only PRIVATE lab from lib/deda_weekly_qa_full_trial.dart
in this branch into the reconstructed 100393 original app. Stage19 verifies
that exact source and metadata, then bumps versionCode to 100394 in a TEMP
isolated Android workspace. No wallet, XP, Cloud Functions or rules changes.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
LAB='lib/deda_weekly_qa_full_trial.dart'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError('NEVER patch original repository files')
    path=project/'internal-build-inputs.json'
    data=json.loads(path.read_text())
    if (data.get('versionCode')!=100393 or
        data.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        data.get('completeOwnerDelivery') is not False or
        data.get('financialRestoreEnabled') is not False or
        data.get('productionExecutionPerformed') is not False or
        data.get('weeklyStage18',{}).get('writesRealWallet') is not False or
        data.get('weeklyStage18',{}).get('writesRealXp') is not False or
        data.get('weeklyStage18',{}).get('writesFirestore') is not False or
        any(not (project/p).is_file() or sha(project/p)!=h
            for p,h in data['sourceHashes'].items())):
        raise ValueError('Require exactly protected original stage18 sandbox')
    source=(project/LAB).read_text()
    if sha(project/LAB)!=sha(ROOT/LAB):
        raise ValueError('Private Stage19 lab code mismatch')
    assert source.count('onTap:previous || settled || busy ? null :')==2
    assert source.count('selectedColor:gold')==2
    assert 'key:ValueKey<int>(selected),' in source
    assert "Text('مركزك المحدد للاختبار: $selected'" in source
    assert "backgroundColor:gold,foregroundColor:navy" in source
    assert "String get key => 'deda_weekly_qa_earned_shadow_v1_$accountKey';" in source
    assert "if(paid.containsKey(id))return state;" in source
    assert "state['paid']=paid;" in source
    assert "if(rank<1||rank>11)throw RangeError('rank');" in source
    assert 'FirebaseFirestore' not in source and 'FirebaseAuth' not in source
    data['versionCode']=100394
    data['weeklyStage19']={
      'original100393Frozen':True,
      'tapAllRanksIncluding11':True,
      'chooseViaDropdownStillWorks':True,
      'highlightSelected':True,
      'readableGoldContrast':True,
      'preserveExistingTest250AndZeroPrize':True,
      'walletOrXpModified':False,
      'productionFirestoreTouched':False,
      'privateQaOnly':True,
    }
    data['purpose']='ORIGINAL 100394 RANK SELECTION OWNER QA, NO LIVE LEAGUE'
    path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
    return data['weeklyStage19']

if __name__=='__main__':
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument('project',type=Path)
    print(json.dumps(bind(cli.parse_args().project),ensure_ascii=False))
