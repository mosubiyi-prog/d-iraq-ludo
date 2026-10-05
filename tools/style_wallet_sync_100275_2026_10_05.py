from pathlib import Path

MAIN = Path('lib/main.dart')
text = MAIN.read_text(encoding='utf-8')
marker = '// DEDA_STYLE_WALLET_SYNC_100275'
if marker in text:
    print('DEDA 100275 wallet sync patch already applied')
    raise SystemExit(0)

if '// DEDA_STYLE_PREVIEW_100274' not in text:
    raise SystemExit('DEDA 100274 preview layer must exist before 100275')

# Keep the last verified GM personal wallet only for the SAME DEDA account.
# This prevents a transient Firestore/readiness failure while opening the style
# shop from replacing the verified personal million with the ordinary balance.
state_anchor = '  static bool _hasGeneralManagerPersonalWallet = false;\n'
if text.count(state_anchor) != 1:
    raise SystemExit(f'100275 GM wallet state anchor count={text.count(state_anchor)}')
text = text.replace(
    state_anchor,
    state_anchor + "  static String _generalManagerPersonalAccountKey = '';\n",
    1,
)

start_token = '    // A protected personal one-million test wallet is available only to an\n'
start = text.find(start_token)
end_token = '    generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;\n'
end = text.find(end_token, start)
if start < 0 or end < 0:
    raise SystemExit('100275 GM load block not found')
end += len(end_token)

replacement = r'''    // Keep one verified manager-personal wallet account-scoped. A temporary
    // backend/readiness failure must never make the purchase page fall back to
    // the ordinary rewarded-diamond balance (for example 18 instead of the
    // manager's 1,000,000). A different account can never inherit this state.
    final gmAccountKey =
        DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    final hadSameVerifiedManagerWallet =
        _hasGeneralManagerPersonalWallet &&
        gmAccountKey.isNotEmpty &&
        _generalManagerPersonalAccountKey == gmAccountKey;

    int? gmPersonal;
    var managerLookupCompleted = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        gmPersonal =
            await DedaBackend.ensureGeneralManagerPersonalDiamondWallet(
          phone: DedaPreferences.phone,
        );
        managerLookupCompleted = true;
        if (gmPersonal != null || attempt == 1) break;
      } catch (_) {
        if (attempt == 1) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    if (gmPersonal != null) {
      _hasGeneralManagerPersonalWallet = true;
      _generalManagerPersonalBalance = gmPersonal;
      _generalManagerPersonalAccountKey = gmAccountKey;
    } else if (!hadSameVerifiedManagerWallet) {
      // For an ordinary/different account, a completed null lookup means there
      // is no authorized GM personal wallet. Also clear stale cross-account
      // state if the backend was temporarily unavailable on a different login.
      _hasGeneralManagerPersonalWallet = false;
      _generalManagerPersonalBalance = 0;
      _generalManagerPersonalAccountKey = '';
    } else if (!managerLookupCompleted) {
      // Same verified manager + temporary backend error: preserve last known
      // personal balance. The purchase path still spends server-side, so this
      // does not create or mint any diamonds locally.
    }
    generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;
'''
text = text[:start] + replacement + text[end:]

style_state = 'class _DedaStylePageState extends State<DedaStylePage> {'
if text.count(style_state) != 1:
    raise SystemExit(f'100275 style state count={text.count(style_state)}')
text = text.replace(style_state, marker + '\n' + style_state, 1)

MAIN.write_text(text, encoding='utf-8')
print('Applied DEDA 100275 account-scoped purchase wallet synchronization')
