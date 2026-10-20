#!/usr/bin/env python3
"""Stage69: align Spark card rules with ACTUAL published Firestore rules.

DOWNLOADS ONLY live ruleset (READ-ONLY); creates ONE ephemeral /tmp candidate.
NEVER pushes or deploys the generated policy. No live Firestore document
read/write. Add the isolated 5000-card receipt path to actual live policy,
not stale checked-in firestore.rules. Prove it in an emulator first.
"""
from pathlib import Path
import json
import os
import sys
import hashlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
from deda_stage66_firestore_only_card_checkout_candidate_NO_DEPLOY import RULE
from deda_stage68_live_wallet_checkout_rules_compat_READONLY import (
    PROJECT, API
)

WALLET='match /deda_diamond_gift_balances/{publicId} {'
OUT=Path('/tmp/deda-stage66-candidate.rules')
MARK='STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY'

def match_end(src:str,from_index:int)->int:
    opening=src.find('{',from_index)
    if opening < 0: raise ValueError('no_wallet_opening')
    depth=0
    for j in range(opening,len(src)):
        if src[j]=='{': depth+=1
        elif src[j]=='}':
            depth-=1
            if depth == 0: return j
    raise ValueError('wallet_unclosed')

def candidate(active:str)->str:
    if active.count(WALLET)!=1 or MARK in active:
        raise ValueError('SAFE_STOP_WALLET_NOT_EXACT_ONCE_OR_ALREADY_PATCHED')
    p=active.index(WALLET)
    end=match_end(active,p)
    wallet=active[p:end+1]
    if 'allow update:' not in wallet and 'allow write:' not in wallet:
        raise ValueError('SAFE_STOP_CANNOT_PROTECT_HISTORIC_CLAIM')
    if 'allow write: if true' in wallet or 'allow update: if true' in wallet:
        raise ValueError('SAFE_STOP_UNCONTROLLED_WALLET_WRITES')
    if active.count('function verifiedDiamondsPersonalOwner(publicId) {')!=1:
        raise ValueError('SAFE_STOP_NO_ORIGINAL_OWNER_PROOF')
    if 'match /deda_stage66_card_receipts/' in active:
        raise ValueError('SAFE_STOP_EXISTING_RECEIPT_ROUTE')
    if not active.strip().startswith("rules_version = '2'"):
        raise ValueError('SAFE_STOP_FIRESTORE_RULES_VERSION_CHANGED')
    extra = """
      // STAGE69_SPARK_ADDITIVE_CARD_ALLOWANCE_OFFLINE_ONLY
      // ALL three writes must commit together; original gift claims retained.
      allow update: if verifiedDiamondsPersonalOwner(publicId)
        && stage66CardSpend(publicId);
"""
    # Add isolated rules/functions at the SAME scope as the wallet match.
    result=active[:p]+RULE+active[p:end]+extra+active[end:]
    if result.count(MARK)!=1 or result.count('STAGE69_SPARK_ADDITIVE_CARD_ALLOWANCE_OFFLINE_ONLY')!=1:
        raise ValueError('SAFE_STOP_STAGE69_MERGE_MISMATCH')
    # Revert generated changes byte-for-byte to prove old live rules untouched.
    reconstructed=result.replace(RULE,'',1).replace(extra,'',1)
    if reconstructed!=active:
        raise ValueError('SAFE_STOP_UNRELATED_LIVE_POLICY_CHANGE')
    return result

def main():
    raw=os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_CI_CREDENTIAL')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info=json.loads(raw)
        if info.get('type')!='service_account' or info.get('project_id')!=PROJECT:
            raise ValueError('project_mismatch')
        credentials=service_account.Credentials.from_service_account_info(
            info,scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http=AuthorizedSession(credentials)
        release=http.get(API+f'projects/{PROJECT}/releases/cloud.firestore',timeout=25)
        if release.status_code!=200: raise ValueError('rules_release_no_read')
        name=release.json().get('rulesetName','')
        if not name.startswith(f'projects/{PROJECT}/rulesets/'): raise ValueError('bad_ruleset')
        current=http.get(API+name,timeout=25)
        if current.status_code!=200: raise ValueError('ruleset_no_read')
        files=current.json().get('source',{}).get('files',[])
        active='\n'.join(f['content'] for f in files
            if isinstance(f,dict) and isinstance(f.get('content'),str)
            and str(f.get('name','')).endswith('.rules'))
        if not active: raise ValueError('empty_rules')
        revised=candidate(active)
        OUT.write_text(revised)
        print('ACTIVE_RULESET_SHA256_PREFIX',hashlib.sha256(active.encode()).hexdigest()[:16])
        print('PASS_STAGE69_LIVE_POLICY_READ_AND_EPHEMERAL_ADDITIVE_CARD_PATCH')
        print('PASS_NO_LIVE_RULE_OR_USER_WRITE_OR_ORIGINAL100_EXPOSURE')
        return 0
    except Exception:
        print('SAFE_STOP_STAGE69_CANNOT_ADAPT_PUBLISHED_RULES')
        return 3
if __name__=='__main__': sys.exit(main())
