#!/usr/bin/env python3
"""Owner 2026-10-21: show ALL personal diamonds & gold in the existing store.

Applies ONLY after actual approved DEDA app was reconstructed and QA32 applied.
No new wallet, checkout, gifted/admin pool, Firebase, entitlement or debit.
Purchasing is unchanged; display now sums ordinary rewards+gifts+verified
GM PERSONAL wallet using same verified presentation as 'ملفي'.
"""
from pathlib import Path

MAIN=Path('lib/main.dart')
MARK='// DEDA_100374_TOTAL_PERSONAL_DIAMONDS_AND_GOLD_DISPLAY_ONLY'
STOCK='    _diamonds = DedaDiamondsWallet.purchasableBalance;'
NEW='''    // DEDA_100374_TOTAL_PERSONAL_DIAMONDS_AND_GOLD_DISPLAY_ONLY
    // SHOW the same complete personal diamond display balance as My Profile.
    // Do not conflate the administrative diamond gift pool or assume this
    // displayed sum is eligible for a debit (wallet spend remains unchanged).
    _diamonds = dedaProfileVisibleDiamonds(
      ordinaryEarnedAndGifted: DedaDiamondsWallet.effectiveBalance,
      hasGeneralManagerPersonalWallet:
          DedaDiamondsWallet.hasGeneralManagerPersonalWallet,
      generalManagerPersonal: DedaDiamondsWallet.generalManagerPersonalBalance,
    );'''
def patch(src):
    if MARK in src:
        if src.count(MARK)!=1:raise ValueError('SAFE_STOP_WALLET_DISPLAY_DUPLICATE')
        return src
    for label,term in {
        'display_source':STOCK,
        'profile_helper':"dedaProfileVisibleDiamonds(",
        'verified_manager_balance':"static int get generalManagerPersonalBalance =>",
        'ordinary_balance':"static int get effectiveBalance =>",
        'gold_coin_display':"value: progress.coins,",
        'wallet_spend':"return DedaDiamondsWallet.spend(price);",
        'gm_ownership_flag':"static bool get hasGeneralManagerPersonalWallet =>",
    }.items():
        if term not in src:
            raise ValueError('SAFE_STOP_WALLET_SOURCE_DRIFT_'+label)
    if src.count(STOCK)!=1:
        raise ValueError('SAFE_STOP_WALLET_BALANCE_MULTIPLE='+str(src.count(STOCK)))
    return src.replace(STOCK,NEW,1)

if __name__=='__main__':
    before=MAIN.read_text()
    after=patch(before)
    if after==before:
        raise SystemExit('SAFE_STOP_DISPLAY_ALREADY_PATCHED')
    MAIN.write_text(after)
    print('PASS_100374_WALLET_SHOP_DISPLAYS_ALL_ACCOUNT_PERSONAL_DIAMONDS')
    print('PASS_100374_GOLD_COINS_RETAIN_REAL_PROGRESS_BALANCE')
    print('PASS_100374_NO_CHANGE_TO_MANAGER_MILLION_SOURCE_OR_PURCHASE_DEBIT')
