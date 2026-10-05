from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')
required = [
    '// DEDA_STYLE_WALLET_SYNC_100275',
    "static String _generalManagerPersonalAccountKey = '';",
    'final hadSameVerifiedManagerWallet =',
    '_generalManagerPersonalAccountKey == gmAccountKey',
    'await DedaBackend.ensureGeneralManagerPersonalDiamondWallet(',
    'generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;',
    '_diamonds = DedaDiamondsWallet.purchasableBalance;',
    "_miniBalanceChip('💎', _diamonds)",
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('DEDA 100275 validator missing: ' + ' | '.join(missing))

# Do not permit the old behavior that unconditionally cleared the verified GM
# personal wallet in the generic catch path.
old_reset = '''    } catch (_) {\n      _hasGeneralManagerPersonalWallet = false;\n      _generalManagerPersonalBalance = 0;\n    }\n'''
if old_reset in text:
    raise SystemExit('DEDA 100275 old unconditional manager-wallet reset remains')

print('DEDA 100275 validator passed: shop uses account-scoped real purchasable wallet')
