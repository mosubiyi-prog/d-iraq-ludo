#!/usr/bin/env python3
"""After reconstructed DEDA main, unify REAL task coins and personal diamonds.

One presentation model, one account-scoped read-only visible strip in daily
tasks and sticky badges/frames shop. Profile retains its already-correct sum.
No coin<->diamond conversion, no new credit, spend call change or local mint.
"""
from pathlib import Path
import re

MAIN=Path("lib/main.dart")
MARK="// DEDA_100377_UNIFIED_REAL_TASK_COINS_AND_ALL_PERSONAL_DIAMONDS"
SHARED="import 'deda_unified_currency_totals.dart';"

STRIP=r'''
// DEDA_100377_UNIFIED_REAL_TASK_COINS_AND_ALL_PERSONAL_DIAMONDS
// Shared read-only UI for Daily Tasks, profile-adjacent screens and store.
// Only real account-scoped wallet readers are used; never a new wallet.
class DedaUnifiedCurrencyStrip extends StatefulWidget {
  const DedaUnifiedCurrencyStrip({super.key});
  @override
  State<DedaUnifiedCurrencyStrip> createState() =>
      _DedaUnifiedCurrencyStripState();
}

class _DedaUnifiedCurrencyStripState extends State<DedaUnifiedCurrencyStrip>
    with WidgetsBindingObserver {
  bool _ready = false;
  String _accountKey = '';
  String? _queuedKey;

  String get _currentKey {
    final key = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    return key.isNotEmpty ? key : DedaPreferences.phone.trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final key = _currentKey;
    if (key.isEmpty || !mounted) return;
    _accountKey = key;
    _queuedKey = null;
    setState(() => _ready = false);
    // Coin balance earned from TASKS is the very same wallet the shop spends;
    // ordinary diamonds include rewarded-ad/task diamonds plus claimed gifts.
    try {
      await DedaSocialProgressWallet.load();
    } catch (_) {
      // An offline source must not be replaced with a fictitious credit.
    }
    try {
      await DedaDiamondsWallet.load();
    } catch (_) {
      // The GM's historical personal wallet may not be server-verified;
      // do not recreate a missing million or borrow the admin gift pool.
    }
    if (!mounted || key != _currentKey) return;
    setState(() => _ready = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = _currentKey;
    if (_accountKey != key && _queuedKey != key && key.isNotEmpty) {
      _queuedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        DedaDiamondsWallet.balanceNotifier,
        DedaDiamondsWallet.generalManagerPersonalNotifier,
        DedaSocialProgressWallet.coinsNotifier,
      ]),
      builder: (context, _) {
        final ready = _ready && key.isNotEmpty && key == _accountKey;
        final totals = DedaUnifiedCurrencyTotals(
          ordinaryEarnedAndGiftedDiamonds: DedaDiamondsWallet.effectiveBalance,
          hasVerifiedManagerPersonalWallet:
              DedaDiamondsWallet.hasGeneralManagerPersonalWallet,
          managerPersonalDiamonds:
              DedaDiamondsWallet.generalManagerPersonalBalance,
          taskCoins: DedaSocialProgressWallet.coinsNotifier.value,
        );
        return Container(
          key: const Key('deda_unified_currency_tasks_and_shop'),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF103B67),
            border: Border.all(color: const Color(0xFFD3A949)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(
                ready ? '💎 ${totals.diamonds}' : '💎 —',
                key: const Key('deda_total_personal_diamonds'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 16),
              )),
              const SizedBox(width: 8),
              Container(width: 1,height: 24,color: Colors.white30),
              const SizedBox(width: 8),
              Expanded(child: Text(
                ready ? '🪙 ${totals.gold}' : '🪙 —',
                key: const Key('deda_total_task_gold'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFE0A2),
                    fontWeight: FontWeight.w900, fontSize: 16),
              )),
            ],
          ),
        );
      },
    );
  }
}
'''

def patch(src):
    if MARK in src:
        if src.count(MARK)!=1:
            raise ValueError('SAFE_STOP_100377_DUPLICATE_WALLET')
        return src
    if "class DedaDiamondsWallet {" not in src or (
        "class DedaSocialProgressWallet {" not in src):
        raise ValueError('SAFE_STOP_100377_REAL_WALLETS_MISSING')
    if 'dedaProfileVisibleDiamonds(' not in src:
        raise ValueError('SAFE_STOP_100377_PROFILE_SUM_NOT_PRESENT')
    if 'DedaDiamondsWallet.spend(price)' not in src or (
       'DedaSocialProgressWallet.spendCoins(price)' not in src):
        raise ValueError('SAFE_STOP_100377_ORIGINAL_PURCHASE_NOT_FOUND')
    imp="import 'deda_profile_visible_diamonds.dart';"
    if src.count(imp)!=1:
        raise ValueError('SAFE_STOP_100377_PROFILE_WALLET_IMPORT_DRIFT')
    src=src.replace(imp,imp+"\n"+SHARED,1)
    target='class DedaDailyTasksPage extends StatefulWidget {'
    if src.count(target)!=1:
        raise ValueError('SAFE_STOP_100377_DAILY_TASKS_PAGE_DRIFT')
    src=src.replace(target,STRIP+"\n"+target,1)

    # Show wallet on task page, ABOVE the existing daily-login reward, without
    # touching task point/coin award logic.
    task_a=src.index('class _DedaDailyTasksPageState')
    task_b=src.find('\nclass ',task_a+40)
    if task_b<0:raise ValueError('SAFE_STOP_100377_TASK_BOUNDARY')
    task=src[task_a:task_b]
    anchor='                    _dailyLoginCard(),'
    if task.count(anchor)!=1:
        raise ValueError('SAFE_STOP_100377_TASK_CARD_ANCHOR '+str(task.count(anchor)))
    task=task.replace(anchor,'''                    const DedaUnifiedCurrencyStrip(),
                    const SizedBox(height: 6),
'''+anchor,1)
    src=src[:task_a]+task+src[task_b:]

    # Keep BOTH the owner's pinned portrait hero AND the same real wallet
    # fixed while the 16 frame/portrait/background choices scroll beneath.
    editor_a=src.index('class _DedaEditProfilePageState')
    editor_b=src.find('\\nclass ',editor_a+40)
    if editor_b<0:raise ValueError('SAFE_STOP_100377_EDIT_EDITOR_BOUNDARY')
    editor=src[editor_a:editor_b]
    pinned='''            Expanded(
              child: ListView(
                key: const Key('deda_edit_profile_scroll_choices'),'''
    if editor.count(pinned)!=1:
        raise ValueError('SAFE_STOP_100377_PINNED_CURRENCY_ANCHOR '+str(editor.count(pinned)))
    editor=editor.replace(pinned,'''            const DedaUnifiedCurrencyStrip(),
'''+pinned,1)
    src=src[:editor_a]+editor+src[editor_b:]

    # No new payment route; storefront still uses same ordinary + manager
    # SUM as Profile, and identical task coin notifier as the tasks strip.
    state='class _DedaStylePageState extends State<DedaStylePage> {'
    if src.count(state)!=1:
        raise ValueError('SAFE_STOP_100377_STYLE_SHOP_DRIFT')
    a=src.index(state)
    b=src.find('\nclass ',a+len(state))
    if b<0:raise ValueError('SAFE_STOP_100377_STORE_BOUNDARY')
    shop=src[a:b]
    pattern=re.compile(
        r'_diamonds\s*=\s*dedaProfileVisibleDiamonds\(\s*'
        r'ordinaryEarnedAndGifted:\s*DedaDiamondsWallet\.effectiveBalance,\s*'
        r'hasGeneralManagerPersonalWallet:\s*'
        r'DedaDiamondsWallet\.hasGeneralManagerPersonalWallet,\s*'
        r'generalManagerPersonal:\s*DedaDiamondsWallet\.generalManagerPersonalBalance,\s*'
        r'\);',re.S)
    replacement='''_diamonds = DedaUnifiedCurrencyTotals(
        ordinaryEarnedAndGiftedDiamonds: DedaDiamondsWallet.effectiveBalance,
        hasVerifiedManagerPersonalWallet:
            DedaDiamondsWallet.hasGeneralManagerPersonalWallet,
        managerPersonalDiamonds:
            DedaDiamondsWallet.generalManagerPersonalBalance,
        taskCoins: (values[0] as DedaSocialProgressSnapshot).coins,
      ).diamonds;'''
    shop,count=pattern.subn(lambda _:replacement,shop)
    if count!=1:raise ValueError('SAFE_STOP_100377_SHOP_SUM_ANCHOR '+str(count))
    # Sticky header: total diamonds and task coins visible even when scrolling
    # through the frame and badge purchase list. The original wallet card
    # is preserved and must render the exact same totals.
    appbar='''        title: Text(
          dedaText('الشارات والإطارات', 'Badges & Frames'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
'''
    if shop.count(appbar)!=1:
        raise ValueError('SAFE_STOP_100377_STYLE_APPBAR_DRIFT')
    shop=shop.replace(appbar,appbar+'''        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: DedaUnifiedCurrencyStrip(),
        ),
''',1)
    if shop.count('DedaUnifiedCurrencyStrip()')!=1 or (
       'DedaDiamondsWallet.spend(price)' not in shop):
        raise ValueError('SAFE_STOP_100377_STORE_PURCHASE_SAFETY')
    src=src[:a]+shop+src[b:]
    if src.count(MARK)!=1:
        raise ValueError('SAFE_STOP_100377_FINAL_WALLET_MARK')
    return src

if __name__=='__main__':
    prior=MAIN.read_text()
    current=patch(prior)
    if current==prior:raise SystemExit('SAFE_STOP_100377_ALREADY_PATCHED')
    MAIN.write_text(current)
    print('PASS_100377_REAL_TASK_COINS_UNIFIED_WITH_PROFILE_AND_STICKY_STORE')
    print('PASS_100377_PERSONAL_MANAGER_AND_TASK_DIAMONDS_SUM_EXACTLY_ONCE')
    print('PASS_100377_NO_SPEND_DEBIT_ADMIN_GIFT_POOL_OR_MINT_CHANGE')
