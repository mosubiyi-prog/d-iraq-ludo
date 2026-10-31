#!/usr/bin/env python3
"""DEDA 100419 owner-approved rules-only activation for legacy Play 340 friends.

This does exactly one production Firestore Rules change: add a guarded
authenticated GET alternative to Stage71 ACTIVE selection. No user data,
wallet, league, owner create/update permission, mobile APK, or Play change.
Requires exact immutable current live SHA and emulator-tested candidate.
"""
import hashlib,json,os,pathlib,requests,sys
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT='deda-25b88'
EXPECTED_LIVE_SHA='ca282cfbb31dae3e934bfb833c4cdc8b5b1714fc27686ffaf2d7296f7436814f'
EXPECTED_RULESET='projects/deda-25b88/rulesets/edb6ba64-21e7-4d90-8ce0-8d506f1191fc'
RELEASE='projects/'+PROJECT+'/releases/cloud.firestore'
API='https://firebaserules.googleapis.com/v1/'
CANDIDATE=pathlib.Path('/tmp/deda100418-current-rule-candidate.rules')
BACKUP=pathlib.Path('/tmp/deda100419-owner-approved-original-ruleset-backup.json')
REPORT=pathlib.Path('/tmp/deda100419-publish-report.json')
ORIGINAL_GET='allow get: if stage71SelfRecipient(originalId);'
ADDED_GET="""allow get: if stage71SelfRecipient(originalId)
        || (signedIn()
          && originalId.matches('^@DEDA-[A-Z0-9]{6}$')
          && exists(/databases/$(database)/documents/deda_share_ids/$(originalId))
          && get(/databases/$(database)/documents/deda_share_ids/$(originalId)).data.kind == 'personal'
          && get(/databases/$(database)/documents/deda_share_ids/$(originalId)).data.active == true
          && (
            resource == null
            || resource.data.keys().hasOnly(['originalId', 'activeId', 'updatedAt'])
          ));"""
MATCH='match /deda_stage71_active_identifier/{originalId} {'
def sha(txt):return hashlib.sha256(txt.encode()).hexdigest()

def session():
    raw=os.getenv('DEDA_SERVICE_ACCOUNT') or os.getenv('DEDA_FALLBACK_ACCOUNT')
    if not raw:raise RuntimeError('SAFE_STOP_NO_FIREBASE_ID_RULES_CREDENTIAL')
    info=json.loads(raw)
    if info.get('project_id')!=PROJECT or info.get('type')!='service_account':
        raise RuntimeError('SAFE_STOP_WRONG_FIREBASE_PROJECT_ACCOUNT')
    cred=Credentials.from_service_account_info(
        info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
    cred.refresh(Request())
    return {'Authorization':'Bearer '+cred.token,'Content-Type':'application/json'}

def request(method,path,headers,payload=None):
    resp=requests.request(method,API+path,headers=headers,json=payload,timeout=50)
    if resp.status_code not in (200,201):
        try:
            err=resp.json().get('error',{})
            label=str(err.get('status','UNKNOWN'))[:50]
        except Exception: label='UNKNOWN'
        raise RuntimeError('SAFE_STOP_FIREBASE_RULES_'+method+'_'+str(resp.status_code)+'_'+label)
    return resp.json()

def read_live(headers):
    rel=request('GET',RELEASE,headers)
    name=rel.get('rulesetName','')
    if not name.startswith('projects/'+PROJECT+'/rulesets/'):
        raise RuntimeError('SAFE_STOP_FIREBASE_RELEASE_INVALID')
    src=request('GET',name,headers).get('source',{}).get('files',[])
    if len(src)!=1 or not isinstance(src[0].get('content'),str):
        raise RuntimeError('SAFE_STOP_MULTIFILE_RULES_UNREVIEWED')
    return name,src[0]['content']

def validate_diff(live,new):
    if sha(live)!=EXPECTED_LIVE_SHA:
        raise RuntimeError('SAFE_STOP_LIVE_RULES_HASH_CHANGED')
    if live.count(MATCH)!=1 or live.count(ORIGINAL_GET)!=1:
        raise RuntimeError('SAFE_STOP_CURRENT_STAGE71_READ_ANCHOR_CHANGED')
    pos=live.index(MATCH)
    tail=live.index('\n    }',pos)
    block=live[pos:tail]
    if block.count(ORIGINAL_GET)!=1:
        raise RuntimeError('SAFE_STOP_GET_NOT_IN_STAGE71')
    if new!=live.replace(ORIGINAL_GET,ADDED_GET,1):
        raise RuntimeError('SAFE_STOP_RULES_NOT_EXACT_SINGLE_GET_CHANGE')
    expected_section=block.replace(ORIGINAL_GET,ADDED_GET,1)
    if expected_section not in new:
        raise RuntimeError('SAFE_STOP_NON_STAGE71_CHANGE')
    if not all(value in block for value in [
       'allow create, update: if stage71SelfRecipient(originalId)',
       'allow list, delete: if false;']):
        raise RuntimeError('SAFE_STOP_STAGE71_OWNER_PROTECTION_DRIFT')
    if len(new)-len(live)!=len(ADDED_GET)-len(ORIGINAL_GET):
        raise RuntimeError('SAFE_STOP_UNEXPECTED_RULES_LENGTH')
    if new.count('match /deda_stage71_active_identifier/{originalId} {')!=1:
        raise RuntimeError('SAFE_STOP_STAGE71_MATCH_MULTIPLE')
    # No other allow, wildcard, collection, or owner function changes.
    print('PASS_100419_ONLY_ONE_STAGE71_AUTHENTICATED_GET_CHANGED')
    print('PASS_100419_OWNER_UPDATE_CREATE_DELETE_LIST_BYTE_PRESERVED')
    print('PASS_100419_EXISTING_PRIZES_ADMINS_AND_ACCOUNT_RULES_BYTE_PRESERVED')

def release_patch(headers,proposed):
    res=request('PATCH',RELEASE+'?updateMask=rulesetName',headers,{
        'name':RELEASE,'release':{'name':RELEASE,'rulesetName':proposed}})
    value=res.get('release',{})
    return (value.get('rulesetName','') if isinstance(value,dict) else '') or res.get('rulesetName','')

def deploy():
    if os.environ.get('DEDA_100419_OWNER_APPROVED_PUBLIC_READ_ONLY')!='YES':
        raise RuntimeError('SAFE_STOP_OWNER_APPROVAL_REQUIRED')
    if not CANDIDATE.is_file():
        raise RuntimeError('SAFE_STOP_NO_EMULATOR_TESTED_CANDIDATE')
    new=CANDIDATE.read_text()
    headers=session()
    original_name,live=read_live(headers)
    if original_name!=EXPECTED_RULESET:
        raise RuntimeError('SAFE_STOP_LIVE_RULESET_NAME_CHANGED')
    validate_diff(live,new)
    BACKUP.write_text(json.dumps({
      'project':PROJECT,'previousRuleset':original_name,
      'previousSha256':sha(live),'candidateSha256':sha(new),
      'scope':'single guarded Stage71 GET only; no data writes',
    },indent=2)+'\n')
    print('PREPARED_SAFE_ROLLBACK_TO',original_name)
    again_name,again=read_live(headers)
    if again_name!=original_name or sha(again)!=sha(live):
        raise RuntimeError('SAFE_STOP_RELEASE_UPDATED_BEFORE_RULESET_CREATE')
    created=request('POST','projects/'+PROJECT+'/rulesets',headers,{
        'source':{'files':[{'name':'firestore.rules','content':new}]}})
    proposed=created.get('name','')
    if not proposed.startswith('projects/'+PROJECT+'/rulesets/'):
        raise RuntimeError('SAFE_STOP_CANDIDATE_RULESET_CREATION_INVALID')
    print('CREATED_REVIEWED_RULESET',proposed)
    again_name,again=read_live(headers)
    if again_name!=original_name or sha(again)!=sha(live):
        raise RuntimeError('SAFE_STOP_RELEASE_CONCURRENT_CHANGE_NO_PATCH')
    try:
        result=release_patch(headers,proposed)
        if result!=proposed:raise RuntimeError('SAFE_STOP_PUBLISH_RESPONSE_MISMATCH')
        verified_name,verified=read_live(headers)
        if verified_name!=proposed or sha(verified)!=sha(new):
            raise RuntimeError('SAFE_STOP_POST_PUBLISH_RULESET_MISMATCH')
        validate_diff(live,verified)
    except Exception:
        # Rollback only our own ruleset; do not undo another administrator's changes.
        active,_=read_live(headers)
        if active==proposed:
            reverted=release_patch(headers,original_name)
            if reverted!=original_name:
                raise RuntimeError('CRITICAL_100419_ROLLBACK_NOT_CONFIRMED')
            after,_=read_live(headers)
            if after!=original_name:
                raise RuntimeError('CRITICAL_100419_ROLLBACK_READBACK_FAILED')
            print('ROLLBACK_DONE_ORIGINAL_FIREBASE_RULES_RESTORED')
        raise
    REPORT.write_text(json.dumps({
      'project':PROJECT,'previousRuleset':original_name,
      'deployedRuleset':proposed,'liveRulesSha256':sha(verified),
      'verified':True,'onlyStage71GetChanged':True,
      'noUserDataMutation':True,'noAppBuild':True,'noPlay':True
    },indent=2)+'\n')
    print('SUCCESS_100419_FIREBASE_PRODUCTION_PUBLIC_ACTIVE_ID_GET_LIVE')
    print('SUCCESS_100419_REAL_FIREBASE_READBACK_SHA256',sha(verified))
    print('SUCCESS_100419_ALL_OTHER_RULES_EXACTLY_PRESERVED')
    print('NO_USER_DATA_WRITES_NO_APK_BUILD_NO_PLAY_PUBLISH')

def verify():
    obj=json.loads(REPORT.read_text())
    if not obj.get('verified') or not obj.get('onlyStage71GetChanged'):
        raise RuntimeError('SAFE_STOP_PUBLISH_REPORT_NOT_VERIFIED')
    name,src=read_live(session())
    if name!=obj['deployedRuleset'] or sha(src)!=obj['liveRulesSha256']:
        raise RuntimeError('SAFE_STOP_PUBLIC_ACTIVE_GET_NO_LONGER_LIVE')
    if ADDED_GET not in src:raise RuntimeError('SAFE_STOP_STAGE71_GET_NOT_ACTIVE')
    if src.count(ADDED_GET)!=1:raise RuntimeError('SAFE_STOP_STAGE71_DUPLICATE')
    print('POSTDEPLOY_SUCCESS_100419_FIREBASE_RULES_LIVE',name)
    print('POSTDEPLOY_SUCCESS_100419_READ_ONLY_PERMISSION_ENABLED')
    print('NO_APK_BUILT_NO_PLAY_NO_USER_DATA_WRITE')

if __name__=='__main__':
    command=sys.argv[1:] if len(sys.argv)>1 else []
    if command==['deploy']:deploy()
    elif command==['verify']:verify()
    else:raise SystemExit('SAFE_STOP_UNRECOGNIZED_100419_ACTION')
