#!/usr/bin/env python3
"""DEDA 100377 point01 compatibility candidate — NO DEPLOY.

Preserve the REAL existing shop's legacy gifted-wallet debit clause and
pending-gift claims; append ONLY receipt-backed atomic LAB frame spending.
This is for emulator validation, not a production security approval.
The historical legacy unreceipted decrease remains a known limitation:
never represent this candidate as universally hardened or SSV-proven.
"""
import hashlib
import json
import os
from pathlib import Path

from deda_stage68_live_wallet_checkout_rules_compat_READONLY import PROJECT, API
from deda_stage69_merge_5000_checkout_into_live_rules_READONLY_NO_DEPLOY import match_end
from deda_owner19_stage52_wallet_rules_candidate_OFFLINE_NO_DEPLOY import (
    GIFT_CLIENT_DECREASE, GIFT_LEGIT_CLAIM
)
from deda_100377_point01_lab_frame_rules_candidate_NO_DEPLOY import RULE

WALLET = 'match /deda_diamond_gift_balances/{publicId} {'
MARK = '// DEDA_100377_POINT01_LEGACY_SHOP_COMPATIBLE_NO_DEPLOY'
OUT = Path('/tmp/deda-point01-legacy-compatible.rules')
ALLOW = """      // DEDA_100377_POINT01_LEGACY_SHOP_COMPATIBLE_NO_DEPLOY
      // EXACT 1000 debit AND immutable frame receipt + entitlement required.
      allow update: if verifiedDiamondsPersonalOwner(publicId)
        && labFrameSpend(publicId);
"""
RULE_COMPAT = RULE.replace(
    '    function labReceiptPath(publicId, frameId) {',
    """    function labWalletPath(publicId) {
      return /databases/$(database)/documents/deda_diamond_gift_balances/$(publicId);
    }
    function labReceiptPath(publicId, frameId) {""",
    1,
).replace('stage66WalletPath(publicId)', 'labWalletPath(publicId)')

def candidate(active: str) -> str:
    if active.count(WALLET) != 1 or active.count(GIFT_CLIENT_DECREASE) != 1:
        raise ValueError('SAFE_STOP_LEGACY_SPEND_RULE_CHANGED')
    if active.count(GIFT_LEGIT_CLAIM) != 1:
        raise ValueError('SAFE_STOP_GIFT_CLAIM_CHANGED')
    if active.count('function verifiedDiamondsPersonalOwner(publicId) {') != 1:
        raise ValueError('SAFE_STOP_OWNER_PROOF_CHANGED')
    if any(term in active for term in (
        MARK, 'match /deda_lab_frame_receipts/',
        'match /deda_lab_owned_frames/',
        'match /deda_stage66_card_receipts/',
    )):
        raise ValueError('SAFE_STOP_EXISTING_CHECKOUT_OR_PATCH')
    if 'allow update: if true' in active or 'allow write: if true' in active:
        raise ValueError('SAFE_STOP_UNCONDITIONAL_WRITE')
    if RULE_COMPAT.count('function labWalletPath(publicId)') != 1:
        raise ValueError('SAFE_STOP_RECEIPT_WALLET_HELPER')
    if 'stage66WalletPath(' in RULE_COMPAT:
        raise ValueError('SAFE_STOP_UNRESOLVED_STAGE66_DEPENDENCY')
    a = active.index(WALLET)
    b = match_end(active, a)
    old_wallet = active[a:b+1]
    if old_wallet.count(GIFT_CLIENT_DECREASE) != 1:
        raise ValueError('SAFE_STOP_LEGACY_SPEND_NOT_WALLET_SCOPED')
    if old_wallet.count(GIFT_LEGIT_CLAIM) != 1:
        raise ValueError('SAFE_STOP_LEGACY_GIFT_NOT_WALLET_SCOPED')
    # Keep EVERY previous rule byte-for-byte; add an extra allow-update branch
    # scoped to atomic frame receipt+ownership only.
    result = active[:a] + RULE_COMPAT + old_wallet[:-1] + ALLOW + '}' + active[b+1:]
    if result.count(MARK) != 1 or result.count(GIFT_CLIENT_DECREASE) != 1:
        raise ValueError('SAFE_STOP_DUPLICATE_OR_MISSING_SECURITY_CLAUSE')
    if result.replace(RULE_COMPAT, '', 1).replace(ALLOW, '', 1) != active:
        raise ValueError('SAFE_STOP_UNRELATED_LIVE_POLICY_CHANGE')
    return result

def main() -> int:
    raw = os.getenv('DEDA_STAGE69_PRIMARY_SA') or os.getenv('DEDA_STAGE69_SECONDARY_SA')
    if not raw:
        print('SAFE_STOP_NO_READONLY_CI_CREDENTIAL')
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        credentials_info = json.loads(raw)
        if (credentials_info.get('type') != 'service_account'
                or credentials_info.get('project_id') != PROJECT):
            raise ValueError('wrong-project')
        cred = service_account.Credentials.from_service_account_info(
            credentials_info, scopes=['https://www.googleapis.com/auth/cloud-platform'])
        http = AuthorizedSession(cred)
        published = http.get(API + f'projects/{PROJECT}/releases/cloud.firestore', timeout=25)
        published.raise_for_status()
        name = published.json().get('rulesetName', '')
        if not name.startswith(f'projects/{PROJECT}/rulesets/'):
            raise ValueError('unexpected-release')
        response = http.get(API + name, timeout=25)
        response.raise_for_status()
        src = response.json().get('source', {}).get('files', [])
        active = '\n'.join(item['content'] for item in src
                           if isinstance(item, dict)
                           and isinstance(item.get('content'), str)
                           and str(item.get('name', '')).endswith('.rules'))
        if not active:
            raise ValueError('empty-rules')
        OUT.write_text(candidate(active))
        print('ACTIVE_RULESET_SHA256_PREFIX', hashlib.sha256(active.encode()).hexdigest()[:16])
        print('PASS_POINT01_LEGACY_SHOP_AND_GIFT_CLAIM_BYTE_IDENTICAL_NO_DEPLOY')
        return 0
    except Exception:
        print('SAFE_STOP_POINT01_CANNOT_PROVE_LIVE_POLICY_COMPATIBILITY')
        return 3

if __name__ == '__main__':
    raise SystemExit(main())
