#!/usr/bin/env python3
"""Point01 OWNER-APPROVED additive Firestore rules deployment.

Preserves every byte of existing wallet/legacy store/gift policy, adds ONLY
1000-diamond receipt-bound premium frame transaction. Published-rules-source
SHA is pinned to the successful 11/11 real-policy-derived emulator run.
Never mutates any user document, wallet, APK or Play. Backup for rollback.
Fail closed on drift, permissions and any test mismatch.
"""
import hashlib
import json
import os
from pathlib import Path

from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from deda_100377_point01_legacy_compatible_rules_NO_DEPLOY import candidate

PROJECT='deda-25b88'
ROOT=f'https://firebaserules.googleapis.com/v1/projects/{PROJECT}'
RELEASE=f'projects/{PROJECT}/releases/cloud.firestore'
SRC=Path('/tmp/deda-point01-legacy-compatible.rules')
BACKUP=Path('/tmp/deda-point01-rollback-private')
EXPECTED_SHA16='12473b12e32f5888'
APPROVAL='2026-10-22-POINT01-LEGACY-SHOP-PRESERVE-APPROVED'
MARKER='DEDA_100377_POINT01_LEGACY_SHOP_COMPATIBLE_NO_DEPLOY'

def fail(why: str):
    raise RuntimeError('SAFE_STOP_POINT01_'+why)

def api(session, method, url, **kw):
    response=session.request(method,url,timeout=35,**kw)
    if response.status_code not in (200,201):
        print('SAFE_STOP_POINT01_API_STATUS',method,response.status_code)
        fail('FIREBASE_API')
    return response.json()

def text_source(obj):
    files=obj.get('source',{}).get('files',[])
    found=[x['content'] for x in files
           if isinstance(x,dict)
           and isinstance(x.get('content'),str)
           and str(x.get('name','')).endswith('.rules')]
    if len(found)!=1: fail('NOT_ONE_RULES_SOURCE')
    return found[0]

def sha(src):
    return hashlib.sha256(src.encode()).hexdigest()

def main():
    if os.getenv('DEDA_POINT01_OWNER_APPROVAL') != APPROVAL:
        fail('OWNER_APPROVAL_MISSING')
    if not SRC.is_file(): fail('EMULATOR_CANDIDATE_MISSING')
    proposed=SRC.read_text()
    if proposed.count(MARKER)!=1: fail('UNEXPECTED_CANDIDATE')
    raw=os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
    if not raw: fail('CREDENTIAL_MISSING')
    info=json.loads(raw)
    if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
        fail('WRONG_PROJECT')
    cred=service_account.Credentials.from_service_account_info(
        info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
    session=AuthorizedSession(cred)
    release_url=f'{ROOT}/releases/cloud.firestore'
    active=api(session,'GET',release_url)
    original_name=active.get('rulesetName','')
    if not original_name.startswith(f'projects/{PROJECT}/rulesets/'):
        fail('UNEXPECTED_RELEASE')
    original=text_source(api(session,'GET',
                        f'https://firebaserules.googleapis.com/v1/{original_name}'))
    if sha(original)[:16]!=EXPECTED_SHA16:
        fail('LIVE_RULES_CHANGED_AFTER_11_TESTS')
    if candidate(original)!=proposed:
        fail('NOT_EXACT_ADDITIVE_EMULATOR_TESTED_POLICY')
    BACKUP.mkdir(parents=True,exist_ok=True)
    (BACKUP/'BEFORE-live-firestore.rules').write_text(original)
    (BACKUP/'CANDIDATE-additive-lab-frames.rules').write_text(proposed)
    (BACKUP/'BEFORE-release.json').write_text(json.dumps({
        'release':RELEASE,'rulesetName':original_name,
        'originalSha256':sha(original),'candidateSha256':sha(proposed),
    },indent=2))
    # Protect other operators' hotfixes from a concurrent overwrite.
    if api(session,'GET',release_url).get('rulesetName')!=original_name:
        fail('CONCURRENT_RELEASE_CHANGED')
    created=api(session,'POST',f'{ROOT}/rulesets',json={
        'source':{'files':[{'name':'firestore.rules','content':proposed}]}})
    new_name=created.get('name','')
    if not new_name.startswith(f'projects/{PROJECT}/rulesets/'):
        fail('INVALID_CREATED_RULESET')
    (BACKUP/'NEW-ruleset-name.txt').write_text(new_name)
    print('PASS_POINT01_IMMUTABLE_RULESET_CREATED')
    try:
        # Double-check the release before switching it.
        if api(session,'GET',release_url).get('rulesetName')!=original_name:
            fail('CONCURRENT_RELEASE_CHANGED_PRE_PATCH')
        api(session,'PATCH',release_url,params={'updateMask':'rulesetName'},
            json={'name':RELEASE,'release':{
                'name':RELEASE,'rulesetName':new_name}})
        current=api(session,'GET',release_url)
        if current.get('rulesetName')!=new_name:
            fail('RELEASE_NOT_MATCHING_CREATED_RULESET')
        confirmed=text_source(api(session,'GET',
            f'https://firebaserules.googleapis.com/v1/{new_name}'))
        if confirmed!=proposed: fail('LIVE_SOURCE_NOT_EXACT_CANDIDATE')
    except Exception:
        try:
            active_now=api(session,'GET',release_url).get('rulesetName')
            if active_now==new_name:
                api(session,'PATCH',release_url,params={'updateMask':'rulesetName'},
                    json={'name':RELEASE,'release':{
                        'name':RELEASE,'rulesetName':original_name}})
                print('PASS_POINT01_AUTOMATIC_RELEASE_ROLLBACK')
        except Exception:
            print('CRITICAL_POINT01_MANUAL_RULES_RELEASE_REVIEW')
        raise
    print('PASS_POINT01_ADDITIVE_FRAME_RULES_LIVE_ORIGINAL_SHOP_AND_GIFTS_PRESERVED')
    print('AFTER_POINT01_SHA256_PREFIX',sha(proposed)[:16])
    print('NO_LIVE_USER_WALLET_DOCUMENTS_OR_PLAY_OR_APK_WRITTEN')

if __name__=='__main__':
    main()
