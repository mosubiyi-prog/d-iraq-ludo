#!/usr/bin/env python3
"""DEDA P09/P04: fail closed for stale in-flight wallet/inventory UI reads.

Patch ONLY the real reconstructed profile cosmetics shop _DedaStylePageState.
No change to paid debits, inventory purchases, Firebase, wallet balances.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = 'DEDA_100377_POINT09_STYLE_PAGE_ASYNC_READ_IDENTITY_GUARD'
CLASS = 'class _DedaStylePageState extends State<DedaStylePage> {'
START = '  Future<void> _load() async {'
STOP = '  void _previewFrame(int index) {'

def patch(source: str) -> str:
    if MARK in source:
        if source.count(MARK) != 1 or source.count('_dedaPoint09StyleReadEpoch') != 3:
            raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_PARTIAL_PATCH')
        return source
    if source.count(CLASS) != 1:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_NOT_UNIQUE')
    a = source.index(CLASS)
    b = source.find('\nclass ', a + len(CLASS))
    if b < 0:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_BOUNDARY')
    body = source[a:b]
    if body.count(START) != 1 or body.count(STOP) != 1:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_SOURCE_DRIFT')
    old_fields = '''  bool _busy = false;
  int? _previewFrameIndex;'''
    new_fields = '''  bool _busy = false;
  // DEDA_100377_POINT09_STYLE_PAGE_ASYNC_READ_IDENTITY_GUARD
  int _dedaPoint09StyleReadEpoch = 0;
  int? _previewFrameIndex;'''
    if body.count(old_fields) != 1:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_STATE_DRIFT')
    body = body.replace(old_fields, new_fields, 1)

    old = '''  Future<void> _load() async {
    final values = await Future.wait<dynamic>(<Future<dynamic>>[
      DedaSocialProgressWallet.load(),
      DedaStyleInventory.load(),
      DedaDiamondsWallet.load(),
    ]);
    if (!mounted) return;
    setState(() {'''
    new = '''  Future<void> _load() async {
    // Capture the initiating account BEFORE any async wallet reads.
    final initiatingPhone = DedaPreferences.phone;
    final initiatingKey =
        DedaBackend.accountKeyForPhone(initiatingPhone).trim();
    final initiatingUid = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser?.uid;
    final readEpoch = ++_dedaPoint09StyleReadEpoch;
    final values = await Future.wait<dynamic>(<Future<dynamic>>[
      DedaSocialProgressWallet.load(),
      DedaStyleInventory.load(),
      DedaDiamondsWallet.load(),
    ]);
    if (!mounted || readEpoch != _dedaPoint09StyleReadEpoch ||
        initiatingPhone != DedaPreferences.phone ||
        initiatingKey !=
            DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim() ||
        initiatingUid != (Firebase.apps.isEmpty
            ? null : FirebaseAuth.instance.currentUser?.uid)) {
      // Do NOT paint another account with a previous user's diamonds,
      // coins, level or cosmetic ownership after late async completion.
      return;
    }
    setState(() {'''
    if body.count(old) != 1:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_LOAD_DRIFT')
    body = body.replace(old, new, 1)
    if body.count('_dedaPoint09StyleReadEpoch') != 3:
        raise ValueError('SAFE_STOP_POINT09_STYLE_PAGE_INCOMPLETE')
    return source[:a] + body + source[b:]

if __name__ == '__main__':
    old = MAIN.read_text(encoding='utf-8')
    updated = patch(old)
    if updated == old:
        raise SystemExit('SAFE_STOP_POINT09_STYLE_PAGE_ALREADY_PATCHED')
    MAIN.write_text(updated, encoding='utf-8')
    print('PASS_POINT09_STYLE_PAGE_PENDING_RESULTS_ACCOUNT_GUARDED')
    print('NO_WALLET_WRITE_NO_CURRENCY_MODIFICATION_NO_APK_NO_PLAY')
