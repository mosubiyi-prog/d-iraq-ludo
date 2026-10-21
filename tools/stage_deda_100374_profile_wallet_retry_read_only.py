#!/usr/bin/env python3
"""Make My Profile re-query its OWN wallet after first frame/app resume.

Read-only authoritative refresh; never recreate the legacy GM 1M, never
transfer between wallets/accounts, never apply a number as a constant.
No timers, fake diamonds or new Firebase writes.
"""
from pathlib import Path

MAIN=Path('lib/main.dart')
NAME='class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
MARK='// DEDA_100374_PROFILE_WALLET_RECHECK_ON_RESUME_NO_MINT'
START='  @override\n  void initState() {'
INIT_ANCHOR='    DedaProfileAppearanceState.syncFromPreferences();\n'
OPEN_EDIT='  Future<void> _openEditProfile() async {'
NEW_CLASS='''class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page>
    with WidgetsBindingObserver {'''

def patch(src):
    if MARK in src:
        if src.count(MARK)!=1:raise ValueError('SAFE_STOP_PROFILE_RETRY_DUPLICATE')
        return src
    if src.count(NAME)!=1:
        raise ValueError('SAFE_STOP_PROFILE_WIDGET_CHANGED')
    a=src.index(NAME)
    b=src.find('\nclass ',a+len(NAME))
    if b<0:b=len(src)
    sec=src[a:b]
    if sec.count(START)<1 or sec.count(INIT_ANCHOR)!=1:
        raise ValueError('SAFE_STOP_PROFILE_INIT_DRIFT')
    if sec.count(OPEN_EDIT)!=1:
        raise ValueError('SAFE_STOP_PROFILE_EDIT_BOUNDARY')
    if 'DedaDiamondsWallet.load()' not in sec:
        raise ValueError('SAFE_STOP_PROFILE_WALLET_SOURCE_MISSING')
    if 'void didChangeAppLifecycleState(' in sec:
        raise ValueError('SAFE_STOP_PROFILE_ALREADY_HAS_LIFECYCLE_OBSERVER')
    sec=sec.replace(NAME,NEW_CLASS,1)
    sec=sec.replace(INIT_ANCHOR,
        '''    DedaProfileAppearanceState.syncFromPreferences();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMyPersonalBalances();
    });
''',1)
    refresh='''  // DEDA_100374_PROFILE_WALLET_RECHECK_ON_RESUME_NO_MINT
  void _refreshMyPersonalBalances() {
    if (!mounted) return;
    unawaited(() async {
      // Uses the existing authenticated/account-key-scoped wallet readers.
      // Failing/offline lookups do NOT imply a deleted manager million.
      try { await DedaDiamondsWallet.load(); } catch (_) {}
      try { await DedaSocialProgressWallet.load(); } catch (_) {}
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshMyPersonalBalances();
    }
  }

'''
    if sec.count('  void dispose() {')==0:
        refresh+='''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

'''
    elif sec.count('  void dispose() {')==1:
        sec=sec.replace('  void dispose() {',
          '  void dispose() {\n    WidgetsBinding.instance.removeObserver(this);',1)
    else:
        raise ValueError('SAFE_STOP_PROFILE_MULTIPLE_DISPOSE')
    sec=sec.replace(OPEN_EDIT,refresh+OPEN_EDIT,1)
    if sec.count(MARK)!=1 or sec.count('WidgetsBinding.instance.addObserver(this);')!=1 or \
       sec.count('WidgetsBinding.instance.removeObserver(this);')!=1:
        raise ValueError('SAFE_STOP_PROFILE_WALLET_REFRESH_POSTCONDITIONS')
    return src[:a]+sec+src[b:]

if __name__=='__main__':
    before=MAIN.read_text()
    after=patch(before)
    if after==before:raise SystemExit('SAFE_STOP_ALREADY_APPLIED')
    MAIN.write_text(after)
    print('PASS_100374_MY_PROFILE_RECHECKS_ACCOUNT_WALLET_ON_RESUME_NO_MINT')
    print('PASS_100374_MY_PROFILE_WATCHER_CLEANUP_AND_COIN_REFRESH')
