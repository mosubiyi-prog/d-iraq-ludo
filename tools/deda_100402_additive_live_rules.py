#!/usr/bin/env python3
"""100402 Firestore-only league: merge an additive block into ACTUAL live Rules.

The deploy workflow MUST emulator-test the exact merged candidate before
changing the live release. Never overwrite currently published wallet rules
from a possibly stale checked-in repo file. No Cloud Functions or billing.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT='deda-25b88'
BASE='https://firebaserules.googleapis.com/v1/'
MARKER='    // DEDA 100402: a small weekly community league'
ANCHOR='    match /system_counters/{counterId} {'

def config():
    tmp=Path(os.environ['RUNNER_TEMP']).resolve()
    if not tmp.is_dir(): raise RuntimeError('NO_RUNNER_TEMP')
    return tmp

def client():
    raw=os.getenv('PRIMARY') or os.getenv('FALLBACK')
    data=json.loads(raw or '{}')
    if data.get('project_id')!=PROJECT or data.get('type')!='service_account':
        raise RuntimeError('WRONG_FIREBASE_PROJECT_ACCOUNT')
    cred=service_account.Credentials.from_service_account_info(
        data,scopes=['https://www.googleapis.com/auth/cloud-platform'])
    return AuthorizedSession(cred),data

def published(api):
    r=api.get(BASE+f'projects/{PROJECT}/releases/cloud.firestore',timeout=22)
    if r.status_code!=200:raise RuntimeError('LIVE_RULES_RELEASE_UNAVAILABLE')
    ruleset=r.json().get('rulesetName','')
    if not ruleset.startswith(f'projects/{PROJECT}/rulesets/'):
        raise RuntimeError('UNEXPECTED_LIVE_RULESET')
    response=api.get(BASE+ruleset,timeout=25)
    if response.status_code!=200:raise RuntimeError('LIVE_RULESET_NOT_READABLE')
    files=response.json().get('source',{}).get('files',[])
    if len(files)!=1 or not isinstance(files[0].get('content'),str):
        raise RuntimeError('MULTIPLE_OR_EMPTY_PUBLISHED_RULES')
    return ruleset,files[0]['content']

def extract():
    repo=Path('firestore.rules').read_text()
    if repo.count(MARKER)!=1 or repo.count(ANCHOR)!=1:
        raise RuntimeError('CANDIDATE_ADDITION_NOT_EXACT')
    return repo[repo.index(MARKER):repo.index(ANCHOR)]

def main():
    phase=sys.argv[1] if len(sys.argv)==2 else ''
    if phase not in ('prepare','predeploy','verify'):raise RuntimeError('UNKNOWN_PHASE')
    tmp=config()
    api,key=client()
    ruleset,live=published(api)
    candidate=tmp/'deda-100402-active-merged.rules'
    recorded=tmp/'deda-100402-original-ruleset.txt'
    block=extract()
    if phase=='prepare':
        if live.count(ANCHOR)!=1 or MARKER in live or \
           'function sameAccount(accountKey)' not in live or \
           'function hasDedaSession(accountKey)' not in live or \
           not live.startswith("rules_version = '2'"):
            raise RuntimeError('SAFE_STOP_LIVE_POLICY_NOT_MERGEABLE')
        merged=live[:live.index(ANCHOR)]+block+live[live.index(ANCHOR):]
        if merged.replace(block,'',1)!=live or merged.count(MARKER)!=1:
            raise RuntimeError('SAFE_STOP_UNRELATED_POLICY_MODIFICATION')
        candidate.write_text(merged)
        (tmp/'deda-100402-live-emulator.json').write_text(json.dumps({
            'firestore':{'rules':str(candidate)},
            'emulators':{'firestore':{'port':8080},'ui':{'enabled':False}}
        }))
        (tmp/'deda-100402-live-deploy.json').write_text(json.dumps({
            'firestore':{'rules':str(candidate)}
        }))
        secret=tmp/'deda-100402-sa.json'
        secret.write_text(json.dumps(key))
        secret.chmod(0o600)
        recorded.write_text(ruleset)
        print('SAFE_MERGE_PREPARED')
        print('PUBLISHED_RULES_PRESERVED_BYTE_FOR_BYTE')
        print('ORIGINAL_RULESET_SHA256_PREFIX='+hashlib.sha256(live.encode()).hexdigest()[:16])
        print('NO_CLOUD_CHANGE_YET')
    elif phase=='predeploy':
        if ruleset!=recorded.read_text().strip() or \
           not candidate.is_file() or \
           candidate.read_text().replace(block,'',1)!=live:
            raise RuntimeError('SAFE_STOP_LIVE_POLICY_CHANGED_BEFORE_DEPLOY')
        print('SAFE_DEPLOY_GUARD_PASSED_PUBLISHED_POLICY_UNCHANGED')
    else:
        if not candidate.is_file() or candidate.read_text()!=live:
            raise RuntimeError('SAFE_STOP_DEPLOYED_CONTENT_DIFFERS_FROM_EMULATOR')
        print('PASS_LIVE_FIRESTORE_RULES_MATCH_TESTED_CANDIDATE')
        print('NO_FUNCTIONS_NO_BILLING_NO_WALLET_DATA_WRITES')

if __name__=='__main__':
    try: main()
    except Exception as e:
        print('SAFE_STOP_'+str(e)[:110])
        sys.exit(2)
