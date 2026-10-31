#!/usr/bin/env python3
"""100418: Minimal authenticated public read of Stage71 ACTIVE ID status.
The existing active record has only originalId, activeId, updatedAt.
Reads deployed rules only and creates an emulator-only candidate. Never deploys.
"""
import hashlib,json,os,pathlib,re,requests
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT='deda-25b88'
OUT=pathlib.Path('/tmp/deda100418-current-rule-candidate.rules')
CONF=pathlib.Path('/tmp/deda100418-emulator-config.json')
def run():
    raw=os.getenv('DEDA_SERVICE_ACCOUNT') or os.getenv('DEDA_FALLBACK_ACCOUNT')
    if not raw: raise SystemExit('SAFE_STOP_NO_READONLY_SERVICE_ACCOUNT')
    info=json.loads(raw)
    if info.get('project_id') != PROJECT: raise SystemExit('SAFE_STOP_WRONG_PROJECT')
    credential=Credentials.from_service_account_info(info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
    credential.refresh(Request())
    h={'Authorization':'Bearer '+credential.token}
    api='https://firebaserules.googleapis.com/v1/'
    def get(url):
        r=requests.get(api+url,headers=h,timeout=30)
        if r.status_code!=200: raise SystemExit('SAFE_STOP_RULES_READ_HTTP_'+str(r.status_code))
        return r.json()
    release=get('projects/'+PROJECT+'/releases/cloud.firestore')
    version=release.get('rulesetName','')
    if not version.startswith('projects/'+PROJECT+'/rulesets/'):
        raise SystemExit('SAFE_STOP_UNKNOWN_RULESET')
    files=get(version).get('source',{}).get('files',[])
    if len(files)!=1 or not isinstance(files[0].get('content'),str):
        raise SystemExit('SAFE_STOP_MULTIFILE_FIRESTORE_RULES')
    live=files[0]['content']
    marker='match /deda_stage71_active_identifier/{originalId} {'
    if live.count(marker)!=1 or live.count('allow get: if stage71SelfRecipient(originalId);')!=1:
        raise SystemExit('SAFE_STOP_STAGE71_LIVE_RULES_DRIFT')
    # Keep all OWNER write rules and Stage71 private registry exactly intact.
    old=marker+'\n      // Canonical original account'
    if old not in live:raise SystemExit('SAFE_STOP_STAGE71_ANCHOR_CHANGED')
    # Exact one-line edit in current Stage71 block; nothing else changes.
    begin=live.index(marker);end=live.index('\n    }',begin)
    portion=live[begin:end]
    before='allow get: if stage71SelfRecipient(originalId);'
    if portion.count(before)!=1:raise SystemExit('SAFE_STOP_ACTIVE_GET_NOT_UNIQUE')
    after="""allow get: if stage71SelfRecipient(originalId)
        || (signedIn()
          && originalId.matches('^@DEDA-[A-Z0-9]{6}$')
          && exists(/databases/$(database)/documents/deda_share_ids/$(originalId))
          && get(/databases/$(database)/documents/deda_share_ids/$(originalId)).data.kind == 'personal'
          && get(/databases/$(database)/documents/deda_share_ids/$(originalId)).data.active == true
          && (
            resource == null
            || resource.data.keys().hasOnly(['originalId', 'activeId', 'updatedAt'])
          ));"""
    patched=portion.replace(before,after)
    if live.count(portion)!=1:raise SystemExit('SAFE_STOP_NONUNIQUE_OLD_BLOCK')
    candidate=live.replace(portion,patched,1)
    if candidate.replace(patched,portion,1)!=live:raise SystemExit('SAFE_STOP_NONADDITIVE_CANDIDATE')
    if candidate.count('match /deda_stage71_active_identifier/{originalId} {')!=1:
        raise SystemExit('SAFE_STOP_MULTIPLE_STAGE71_RULES')
    OUT.write_text(candidate)
    CONF.write_text(json.dumps({'firestore':{'rules':str(OUT)},
       'emulators':{'firestore':{'host':'127.0.0.1','port':8096},'ui':{'enabled':False}}}))
    print('PASS_RULESET_READ_ONLY',version)
    print('PASS_ACTUAL_LIVE_RULES_SHA256',hashlib.sha256(live.encode()).hexdigest())
    print('PASS_ADD_ONLY_AUTHENTICATED_ACTIVE_IDENTIFIER_GET',hashlib.sha256(candidate.encode()).hexdigest())
    print('PASS_STAGE71_OWNER_WRITES_UNTOUCHED')
    print('NO_FIREBASE_RELEASE_PATCH_NO_USER_DOCUMENT_READ_NO_USER_DATA_WRITE_NO_PLAY')
if __name__=='__main__':run()
