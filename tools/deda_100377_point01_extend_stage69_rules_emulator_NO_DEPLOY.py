#!/usr/bin/env python3
"""Extend Stage69 READ-ONLY published-policy candidate in /tmp for emulator.

Never deploy. MUST fail if original policy/hardened wallet do not match.
"""
from pathlib import Path
from deda_100377_point01_lab_frame_rules_candidate_NO_DEPLOY import (
    RULE, OLD, NEW, WALLET, MARK, match_end
)
BASE=Path('/tmp/deda-stage66-candidate.rules')
OUT=Path('/tmp/deda-point01-frame-candidate.rules')
def extend(base: str) -> str:
    if base.count(WALLET) != 1 or base.count(OLD) != 1:
        raise ValueError('SAFE_STOP_STAGE69_WALLET_NOT_EXACT')
    if MARK in base or 'match /deda_lab_frame_receipts/' in base:
        raise ValueError('SAFE_STOP_POINT01_ALREADY_EXISTS')
    a=base.index(WALLET)
    b=match_end(base,a)
    wallet=base[a:b+1]
    if wallet.count(OLD)!=1:
        raise ValueError('SAFE_STOP_NO_PROTECTED_WALLET_BRANCH')
    amended=base[:a]+RULE+wallet.replace(OLD,NEW,1)+base[b+1:]
    if amended.count(MARK)!=1:
        raise ValueError('SAFE_STOP_POINT01_CANDIDATE_BAD_MARKER')
    if amended.replace(RULE,'',1).replace(NEW,OLD,1)!=base:
        raise ValueError('SAFE_STOP_POINT01_UNRELATED_POLICY_CHANGE')
    return amended
if __name__=='__main__':
    if not BASE.is_file():
        raise SystemExit('SAFE_STOP_NO_STAGE69_READONLY_POLICY')
    data=extend(BASE.read_text())
    OUT.write_text(data)
    print('PASS_POINT01_READONLY_STAGE69_WALLET_PLUS_13_FRAME_1000_CANDIDATE_NO_DEPLOY')
