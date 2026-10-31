"""DEDA 100403: 100402->100403 ONLY first opening session / start countdown.

No changes to original XP, money, Firestore backend, app authentication logic.
Only the two owner-approved league routes, account-view gate and manifest.
"""
from pathlib import Path
import hashlib
import json
import re
import argparse

ROOT=Path(__file__).resolve().parents[3]
GATE=Path('lib/deda_weekly_account_view_gate.dart')
MAIN=Path('lib/main.dart')
PAGE=Path('lib/deda_weekly_leaderboard_page.dart')

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    p=Path(project).resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents:
        raise ValueError('Refuse to modify official repository')
    manifest=p/'internal-build-inputs.json'
    data=json.loads(manifest.read_text())
    if (data.get('versionCode')!=100402 or
        data.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        data.get('variant')!='candidate' or
        data.get('productionExecutionPerformed') is not False or
        data.get('financialRestoreEnabled') is not False or
        data.get('weekly100402FirestoreDirect',{}).get('noCloudFunctionsOrBilling') is not True):
        raise ValueError('Unknown 100402 build input: abort')
    for name, expected in data['sourceHashes'].items():
        f=p/name
        if not f.is_file() or sha(f)!=expected:
            raise ValueError('Original signed app input differs: '+name)
    current=p/GATE
    approved=(ROOT/GATE).read_text()
    if ('_authReady' not in approved or
        "'جاري تهيئة حساب الدوري...'" not in approved or
        "deda_weekly_prestart_countdown" not in approved):
        raise ValueError('New first-open protection is missing')
    if current.read_text()!=approved:
        raise ValueError('Expected new gate already pinned in 100402 source build')
    main=(p/MAIN).read_text()
    anchor="DedaWeeklyAccountViewGate(\n        readCanonicalAccount:"
    replacement="DedaWeeklyAccountViewGate(\n        startsAt: DateTime.utc(2026, 10, 31, 3),\n        readCanonicalAccount:"
    if main.count(anchor)!=2 or replacement in main:
        raise ValueError('Both official league routes must match before update')
    result=main.replace(anchor,replacement)
    if result.count(replacement)!=2:
        raise ValueError('Unexpected edited original navigation')
    (p/MAIN).write_text(result)
    # Old local-QA footer must not describe verified Firestore ranks as local.
    page=p/PAGE
    ui=page.read_text()
    notice="widget.privateTrialXp != null && !previousWeek"
    if ui.count(notice)!=1:
        raise ValueError('Expected exactly one local-trial footer')
    page.write_text(ui.replace(
        notice,"widget.privateTrialXp != null && !previousWeek && !view.verified",1
    ))
    data['sourceHashes'][str(PAGE)]=sha(page)
    data['sourceHashes'][str(MAIN)]=sha(p/MAIN)
    data['sourceHashes'][str(GATE)]=sha(current)
    data['versionCode']=100403
    data['weekly100403FirstOpenGate']={
        'originalVersionCode':100402,
        'waitsForInitialFirebaseAuthEmission':True,
        'doesNotTreatMissingInitialUidAsLogout':True,
        'revokesOnVerifiedAccountSwitch':True,
        'showBaghdad6amCountdownBeforeStart':True,
        'officialHomeRoutes':2,
        'originalLevelXPAndDiamondsModified':False,
        'firebaseRulesReDeployed':False,
    }
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    return data['weekly100403FirstOpenGate']

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('project',type=Path)
    print(json.dumps(bind(ap.parse_args().project),ensure_ascii=False))
