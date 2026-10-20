#!/usr/bin/env python3
"""Stage68: READ ONLY published DEDA Firestore wallet policy compatibility.

This fetches the ACTIVE Firestore ruleset via the Google Rules API using the
existing CI service account. It does not print rule source, user data or
credentials, and performs no Firestore document or rules writes.
"""
import json
import os
import hashlib
from pathlib import Path
import sys

PROJECT = 'deda-25b88'
API = 'https://firebaserules.googleapis.com/v1/'
RULES = Path('firestore.rules')
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0,str(SCRIPT_DIR))
from deda_stage66_firestore_only_card_checkout_candidate_NO_DEPLOY import make as stage66_make

def section(src, marker):
    if src.count(marker) != 1: return ''
    a = src.index(marker)
    start = src.find('{',a)
    if start < 0: return ''
    level = 0
    for i in range(start,len(src)):
        if src[i] == '{': level += 1
        elif src[i] == '}':
            level -= 1
            if level == 0: return src[a:i+1]
    return ''

def analyze(active):
    wallet = section(active,'match /deda_diamond_gift_balances/{publicId} {')
    own = section(active,'function verifiedDiamondsPersonalOwner(publicId) {')
    gm = section(active,'match /deda_gm_personal_diamond_wallets/{accountKey} {')
    try:
        candidate = stage66_make(active)
        source_compatible = 'STAGE66_FIRESTORE_ONLY_CANDIDATE_NO_DEPLOY' in candidate
    except Exception:
        source_compatible = False
    return {
        'active_rules_identical_to_repo': active.strip() == RULES.read_text().strip(),
        'gift_balance_section_present': bool(wallet),
        'gift_wallet_customer_read_rule_present':
            bool(wallet) and 'allow get:' in wallet,
        'verified_gift_original_owner_function_present':bool(own),
        'manager_wallet_section_present':bool(gm),
        'wallet_client_unreceipted_debit_clause_detected':
            bool(wallet) and (
                'balance <= resource.data.balance' in wallet or
                'balance < resource.data.balance' in wallet),
        'stage66_rules_can_be_applied_unchanged_to_active': source_compatible,
        'already_has_stage66_signed_receipts':
            'match /deda_stage66_card_receipts/' in active,
        'READ_ONLY_NO_USER_DATA_NO_DEPLOY':True,
    }

def main():
    raw = os.getenv('DEDA_STAGE68_PRIMARY_SA') or os.getenv('DEDA_STAGE68_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_CREDENTIAL')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        value = json.loads(raw)
        if value.get('type') != 'service_account' or value.get('project_id') != PROJECT:
            raise ValueError('invalid project')
        credential = service_account.Credentials.from_service_account_info(
            value,scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http = AuthorizedSession(credential)
        release = http.get(API+'projects/'+PROJECT+'/releases/cloud.firestore',timeout=25)
        if release.status_code != 200:
            print('SAFE_STOP_NO_ACTIVE_RULESET_ACCESS',release.status_code)
            return 3
        name = release.json().get('rulesetName','')
        if not name.startswith('projects/'+PROJECT+'/rulesets/'):
            print('SAFE_STOP_INVALID_RULESET_REF')
            return 4
        active_response=http.get(API+name,timeout=25)
        if active_response.status_code != 200:
            print('SAFE_STOP_NO_ACTIVE_RULESET_READ',active_response.status_code)
            return 5
        rows=active_response.json().get('source',{}).get('files',[])
        live='\n'.join(row['content'] for row in rows if isinstance(row,dict)
                       and isinstance(row.get('content'),str)
                       and str(row.get('name','')).endswith('.rules'))
        if len(live)<100:
            print('SAFE_STOP_INVALID_LIVE_RULES')
            return 6
        print('ACTIVE_RULESET_SHA256_PREFIX',hashlib.sha256(live.encode()).hexdigest()[:16])
        for key,flag in analyze(live).items():
            print('ACTIVE_RULE_'+key.upper(),flag)
        print('FINISHED_STAGE68_READ_ONLY_NO_ACCOUNT_OR_RULE_WRITE')
        return 0
    except Exception:
        print('SAFE_STOP_RULES_READ_FAILED_NO_SENSITIVE_CONTENT')
        return 7
if __name__ == '__main__': sys.exit(main())
