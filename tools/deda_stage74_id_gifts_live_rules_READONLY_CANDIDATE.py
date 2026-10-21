#!/usr/bin/env python3
"""Stage74 add-only Hadaya ID gift receipt on exact currently LIVE Stage72.

Read live DEDA Firestore rules through the CI service account READ ONLY.
Generate a TEMPORARY rules file for the emulator; never deploy here.
Harden only the stage71 active-alias rule so an unclaimed GIFTED identifier
cannot be activated until the real recipient's immutable receipt exists.
Original diamonds, gift ledger, places, apps, accounts, GM100 remain untouched.
"""
import hashlib
import json
import os
from pathlib import Path

PROJECT='deda-25b88'
OUT=Path('/tmp/deda-stage74-gifts-candidate.rules')
MARK='STAGE74_HADAYA_FREE_ID_GIFT_RECEIPT_ONLY'
BASE_MARK='STAGE71_FREE_DUAL_200_ROLE_AND_UNIQUE_GRANT_NO_DEPLOY'
RECEIPT_RULE="""
    // STAGE74_HADAYA_FREE_ID_GIFT_RECEIPT_ONLY
    function stage74ReceiptPath(identifier) {
      return /databases/$(database)/documents/deda_stage74_id_gift_receipts/$(identifier);
    }
    function stage74ReceivedByOwner(identifier, originalId) {
      return exists(stage74ReceiptPath(identifier))
        && get(stage74ReceiptPath(identifier)).data.originalId == originalId
        && get(stage74ReceiptPath(identifier)).data.identifier == identifier;
    }
    match /deda_stage74_id_gift_receipts/{identifier} {
      // Public identifier gift receipts are private to the verified recipient.
      // A missing receipt must also be readable in a Firestore transaction
      // so first-time acceptance can check it does not exist. Ownership is
      // always resolved from the immutable original gift registry.
      allow get: if signedIn()
        && exists(stage71RegistryPath(identifier))
        && get(stage71RegistryPath(identifier)).data.recipientOriginalId is string
        && stage71SelfRecipient(
             get(stage71RegistryPath(identifier)).data.recipientOriginalId);
      allow list: if signedIn()
        && resource.data.originalId is string
        && stage71SelfRecipient(resource.data.originalId);
      allow update, delete: if false;
      allow create: if signedIn()
        && request.resource.data.identifier == identifier
        && request.resource.data.originalId is string
        && request.resource.data.group in ['001','002']
        && request.resource.data.receivedAt == request.time
        && request.resource.data.keys().hasOnly([
          'identifier','originalId','group','receivedAt'
        ])
        && stage71SelfRecipient(request.resource.data.originalId)
        && exists(stage71RegistryPath(identifier))
        && get(stage71RegistryPath(identifier)).data.identifier == identifier
        && get(stage71RegistryPath(identifier)).data.kind == 'gifted'
        && get(stage71RegistryPath(identifier)).data.recipientOriginalId ==
          request.resource.data.originalId
        && get(stage71RegistryPath(identifier)).data.group ==
          request.resource.data.group;
    }

"""

def candidate(live):
    if not live.strip().startswith("rules_version = '2'"):
        raise ValueError('STAGE74_UNKNOWN_LIVE_RULES_VERSION')
    if MARK in live or live.count(BASE_MARK)!=1:
        raise ValueError('STAGE74_WRONG_OR_ALREADY_UPDATED_LIVE_RULES')
    root='match /databases/{database}/documents {'
    start='match /deda_stage71_active_identifier/{originalId} {'
    if live.count(root)!=1 or live.count(start)!=1:
        raise ValueError('STAGE74_EXPECTED_SINGLE_DOCUMENTS_ROOT_AND_ACTIVE_ALIAS')
    i=live.index(start)
    end=live.index('\n    }',i)+len('\n    }')
    old=live[i:end]
    proof='&& get(stage71RegistryPath(request.resource.data.activeId)).data.recipientOriginalId == originalId'
    if old.count(proof)!=1: raise ValueError('STAGE74_ACTIVE_ALIAS_PROOF_MOVED')
    hardened=old.replace(proof,proof+"""
            && (
              get(stage71RegistryPath(request.resource.data.activeId)).data.kind == 'self_used'
              || stage74ReceivedByOwner(request.resource.data.activeId, originalId)
            )""",1)
    rebuilt=live[:i]+hardened+live[end:]
    rebuilt=rebuilt.replace(root,root+'\n'+RECEIPT_RULE,1)
    if rebuilt.count(MARK)!=1 or rebuilt.count('match /deda_stage74_id_gift_receipts/')!=1:
        raise ValueError('STAGE74_DUPLICATE_RECEIPT_RULE')
    # EXACT reverse: prove no modification except single active-alias AND and
    # additive receipt security match. No old diamonds/gifts can be changed.
    reversed_text=rebuilt.replace('\n'+RECEIPT_RULE,'',1)
    reversed_text=reversed_text.replace(hardened,old,1)
    if reversed_text!=live:raise ValueError('STAGE74_OLD_POLICIES_MODIFIED')
    return rebuilt

def main():
    raw=os.getenv('DEDA_STAGE71_PRIMARY_SA') or os.getenv('DEDA_STAGE71_SECONDARY_SA')
    if not raw: raise ValueError('NO_PRIVATE_CI_READONLY_SERVICE_ACCOUNT')
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    info=json.loads(raw)
    if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
        raise ValueError('WRONG_DEDA_PROJECT')
    creds=service_account.Credentials.from_service_account_info(info,
        scopes=['https://www.googleapis.com/auth/cloud-platform'])
    session=AuthorizedSession(creds)
    release=session.get(f'https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases/cloud.firestore',timeout=25)
    release.raise_for_status()
    ruleset=release.json().get('rulesetName','')
    if not ruleset.startswith(f'projects/{PROJECT}/rulesets/'):
        raise ValueError('WRONG_LIVE_RULESET')
    res=session.get('https://firebaserules.googleapis.com/v1/'+ruleset,timeout=25)
    res.raise_for_status()
    files=res.json().get('source',{}).get('files',[])
    sources=[x['content'] for x in files if x.get('name','').endswith('.rules')]
    if len(sources)!=1:raise ValueError('EXPECT_EXACT_ONE_LIVE_RULES_FILE')
    live=sources[0]
    final=candidate(live)
    OUT.write_text(final)
    print('PASS_STAGE74_BEFORE_SHA256',hashlib.sha256(live.encode()).hexdigest())
    print('PASS_STAGE74_CANDIDATE_SHA256',hashlib.sha256(final.encode()).hexdigest())
    print('PASS_STAGE74_LIVE_POLICY_READ_ONLY_HADAYA_RECEIPT_AND_RECEIVED_ALIAS_GUARD')

if __name__=='__main__':
    main()
