#!/usr/bin/env python3
"""Point04: stop stale received-gift DIAMONDS leaking between accounts on offline refresh.

A single real account keeps its previously verified gift value if network
refresh fails, but a DIFFERENT account must never inherit another account's
last seen gift balance or a late async gift-read. This changes DISPLAY CACHE
ownership only: do not mint/debit currency, rewrite old manager million, change
existing badges checkout, or merge general manager administrative gift pool.
Applied only to the reconstructed real Flutter source after Points01-03.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT04_GIFT_BALANCE_ACCOUNT_SCOPED_READ_ONLY'
STATE = '  static int _giftedBalance = 0;'
START = 'class DedaDiamondsWallet {'
LOAD = '  static Future<DedaDiamondsState> load() async {'
ORIGINAL = """    _localBalance = balance;
    // Gift credits live on Firestore and are keyed by the stable personal DEDA
    // ID. A temporary network failure never erases the last known gift value.
    final publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    if (publicId.isNotEmpty) {
      try {
        _giftedBalance =
            await DedaBackend.personalGiftedDiamondBalance(publicId);
      } catch (_) {}
    }
"""
REPLACEMENT = """    _localBalance = balance;
    // DEDA_100377_POINT04_GIFT_BALANCE_ACCOUNT_SCOPED_READ_ONLY
    // On the SAME signed-in account, a network failure preserves last-read
    // gifted diamonds. Switching accounts must discard that cached value.
    final giftAccountScope = _accountScope();
    if (_giftedBalanceAccountScope != giftAccountScope) {
      _giftedBalance = 0;
      _giftedBalanceAccountScope = giftAccountScope;
    }
    final publicId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    if (publicId.isNotEmpty) {
      try {
        final serverGifted =
            await DedaBackend.personalGiftedDiamondBalance(publicId);
        // A late response from an old account must NOT repopulate this cache
        // if the user switched phone/account during the network request.
        if (_giftedBalanceAccountScope == giftAccountScope &&
            _accountScope() == giftAccountScope) {
          _giftedBalance = serverGifted;
        }
      } catch (_) {
        // Offline: only retain the current account's previously read amount.
      }
    }
"""


def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1 or src.count('_giftedBalanceAccountScope') < 3:
            raise ValueError('SAFE_STOP_POINT04_PARTIAL_ACCOUNT_SCOPE')
        return src
    if src.count(START) != 1 or src.count(LOAD) != 1:
        raise ValueError('SAFE_STOP_POINT04_REAL_WALLET_NOT_UNIQUE')
    if src.count(STATE) != 1 or src.count(ORIGINAL) != 1:
        raise ValueError('SAFE_STOP_POINT04_EXISTING_GIFT_REFRESH_DRIFT')
    a = src.index(START)
    b = src.find('\nclass ', a + len(START))
    if b < 0:
        raise ValueError('SAFE_STOP_POINT04_WALLET_BOUNDARY')
    section = src[a:b]
    for protected in (
        'static Future<bool> spend(int amount) async {',
        'await DedaBackend.spendGeneralManagerPersonalDiamonds(',
        'await DedaBackend.spendPersonalGiftedDiamonds(',
        'ensureGeneralManagerPersonalDiamondWallet(',
        'static int get effectiveBalance => _localBalance + _giftedBalance;',
    ):
        if protected not in section:
            raise ValueError('SAFE_STOP_POINT04_PROTECTED_WALLET_SOURCE_MISSING:' + protected)
    section = section.replace(STATE, STATE + "\n  static String _giftedBalanceAccountScope = '';", 1)
    section = section.replace(ORIGINAL, REPLACEMENT, 1)
    edited = src[:a] + section + src[b:]
    if edited.count(MARK) != 1:
        raise ValueError('SAFE_STOP_POINT04_MARKER_COUNT')
    if edited.count('static Future<bool> spend(int amount) async {') != src.count('static Future<bool> spend(int amount) async {'):
        raise ValueError('SAFE_STOP_POINT04_SPEND_MUTATED')
    if 'DedaUnifiedCurrencyTotals(' not in edited:
        raise ValueError('SAFE_STOP_POINT04_EXISTING_UNIFIED_WALLET_ABSENT')
    return edited


if __name__ == '__main__':
    old = MAIN.read_text(encoding='utf-8')
    new = patch(old)
    if new == old:
        raise SystemExit('SAFE_STOP_POINT04_ALREADY_PRESENT')
    MAIN.write_text(new, encoding='utf-8')
    print('PASS_POINT04_CACHED_GIFTED_DIAMONDS_STAY_WITH_SAME_ACCOUNT_ONLY')
    print('PASS_POINT04_LATE_ACCOUNT_SWITCH_GIFT_RESPONSE_IGNORED')
    print('PASS_POINT04_NO_ADMIN_POOL_NO_MANAGER_MILLION_MINT_OR_SHOP_DEBIT_CHANGE')
