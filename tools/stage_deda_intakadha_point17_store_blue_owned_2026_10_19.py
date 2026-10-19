#!/usr/bin/env python3
"""DEDA stage17: move four paid ID-card actions into store and keep My IDs compact.

Runs ONLY after reconstructed 100356 + stages 2..16. Does not edit checked-in
lib/main.dart, deploy Firebase, spend local diamonds, expose private first 100,
or enable real purchases. Stage16 server flag remains OFF by default.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
ACCOUNT_END = "class DedaDiamondsState {"
SHOP = "class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {"
SHOP_END = "class DedaPoint10CandidateGroup002 {"
OLD_ACCOUNT_PAID = """          DedaPoint14VerifiedAccountPanel(
            identifier: originalId,
          ),
          const SizedBox(height: 14),
          DedaPoint15OwnedIdentifierPanel(originalId: originalId),
          const SizedBox(height: 8),
"""
BLUE = "            _ownedIdsCompactCard(),\n"
OWNED_BELOW_BLUE = """            _ownedIdsCompactCard(),
            const SizedBox(height: 5),
            DedaPoint15OwnedIdentifierPanel(
              originalId: DedaBackend.personalShareIdForPhone(
                DedaPreferences.phone,
              ).trim(),
            ),
"""
OLD_NOTE = """            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                dedaText(
                  'المعرّفات المميزة المملوكة تظهر بعد ربط الملكية والتحقق منها. الاستبدال متوقف لحمايتك.',
                  'Owned premium identifiers appear after verified ownership linking. Switching is disabled for safety.',
                ),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF626F6B),
                ),
              ),
            ),
"""
SHOP_INSERT = """          const SizedBox(height: 3),
          DedaPoint17ShopCardAction(
            identifier: widget.identifier,
            color: color,
          ),
"""
CARD_TAIL = """          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {"""
NEW_CARD_TAIL = """          ),
""" + SHOP_INSERT + """        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {"""
SHOP_LIFECYCLE = """  @override
  void initState() {
    super.initState();
    DedaPoint16PremiumCallableBridge.configure();
    DedaPoint14VerifiedBridge.refresh(widget.identifier);
  }

  @override
  void didUpdateWidget(covariant DedaIdentifierStorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      DedaPoint14VerifiedBridge.refresh(widget.identifier);
    }
  }

"""
NEW_ACTIONS = r'''// DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19
// The STORE owns purchase/use controls. Account info only has its sapphire
// "My IDs" card and verified owned IDs. No price/buy buttons in that editor.
// Live flag OFF => buttons cannot charge, falsely own, or change a profile.
class DedaPoint17ShopCardAction extends StatefulWidget {
  final String identifier;
  final DedaPremiumIdCardColor color;
  const DedaPoint17ShopCardAction({
    super.key, required this.identifier, required this.color,
  });

  @override
  State<DedaPoint17ShopCardAction> createState() =>
      _DedaPoint17ShopCardActionState();
}

class _DedaPoint17ShopCardActionState
    extends State<DedaPoint17ShopCardAction> {
  bool _busy = false;
  String? _requestId;
  int _epoch = 0;

  @override
  void didUpdateWidget(covariant DedaPoint17ShopCardAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier ||
        oldWidget.color != widget.color) {
      _epoch++;
      _busy = false;
      _requestId = null;
    }
  }

  Future<void> _act(bool owned) async {
    if (_busy || !DedaPoint16PremiumCallableBridge.enabled ||
        DedaPoint14VerifiedBridge.readRemote == null ||
        DedaPoint14VerifiedBridge.activateRemote == null) return;
    final openingId = widget.identifier;
    final openingColor = widget.color;
    final epoch = _epoch;
    final checked = DedaPoint14VerifiedBridge.notifier.value;
    if (checked == null || !checked.validFor(openingId)) return;
    if (owned && !checked.owned.contains(openingColor)) return;
    if (!owned && (checked.owned.contains(openingColor) ||
        DedaPoint16PremiumCallableBridge.enabled == false)) return;
    if (!owned) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dedaText('تأكيد شراء البطاقة', 'Confirm card purchase')),
          content: Text(dedaText(
            'شراء تصميم البطاقة بـ5,000 ماسة؟ سعر المعرّف منفصل: 10,000 ماسة.',
            'Buy this card design for 5,000 diamonds? An identifier costs 10,000 separately.',
          )),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dedaText('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dedaText('تأكيد الشراء', 'Confirm purchase')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || epoch != _epoch ||
          widget.identifier != openingId || _busy) return;
    }
    setState(() => _busy = true);
    var success = false;
    try {
      if (owned) {
        success = await DedaPoint14VerifiedBridge.useOwned(
          openingId, openingColor);
      } else {
        final reqId = _requestId ??= DateTime.now().toUtc()
            .microsecondsSinceEpoch.toString() + '-' + openingColor.name;
        final receipt = await DedaPoint16PremiumCallableBridge.checkoutCard(
          openingColor, reqId);
        if (!receipt.serverConfirmed || receipt.color != openingColor ||
            receipt.transactionId.trim().isEmpty ||
            (receipt.alreadyOwned && receipt.diamondsCharged != 0) ||
            (!receipt.alreadyOwned && receipt.diamondsCharged != 5000)) {
          throw StateError('unverified-card-receipt');
        }
        final refreshed = await DedaPoint16PremiumCallableBridge.readOwnedColors(
          openingId);
        if (!refreshed.contains(openingColor)) {
          throw StateError('card-entitlement-unconfirmed');
        }
        if (!mounted || epoch != _epoch ||
            widget.identifier != openingId) return;
        await DedaPoint14VerifiedBridge.refresh(openingId);
        final after = DedaPoint14VerifiedBridge.notifier.value;
        success = after != null && after.validFor(openingId) &&
            after.owned.contains(openingColor);
      }
    } catch (_) {
      // Never grant ownership locally or debit SharedPreferences on failure.
      success = false;
    } finally {
      if (mounted && epoch == _epoch &&
          widget.identifier == openingId) {
        setState(() => _busy = false);
      }
    }
    if (!mounted || epoch != _epoch || widget.identifier != openingId) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? owned
              ? dedaText('تم تفعيل البطاقة على ملفك', 'Card activated')
              : dedaText('تم إثبات شراء البطاقة. اضغط استخدام.', 'Card owned. Tap Use.')
          : dedaText('تعذر التأكيد من الخادم؛ لم تتغير الملكية أو البطاقة.',
              'Server verification failed; card and ownership unchanged.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DedaPoint14VerifiedSnapshot?>(
      valueListenable: DedaPoint14VerifiedBridge.notifier,
      builder: (context, snapshot, _) {
        final state = snapshot != null && snapshot.validFor(widget.identifier)
            ? snapshot : null;
        final owned = state?.owned.contains(widget.color) ?? false;
        final active = owned && state?.active == widget.color;
        final serverReady = DedaPoint16PremiumCallableBridge.enabled &&
            DedaPoint14VerifiedBridge.readRemote != null &&
            DedaPoint14VerifiedBridge.activateRemote != null &&
            state != null;
        return SizedBox(
          height: 31,
          child: OutlinedButton(
            key: ValueKey<String>('deda_point17_shop_action_' + widget.color.name),
            onPressed: _busy || active || !serverReady
                ? null : () => _act(owned),
            child: Text(
              active
                  ? dedaText('مستخدمة حاليًا', 'In use')
                  : owned
                      ? dedaText('استخدام', 'Use')
                      : serverReady
                          ? dedaText('شراء بـ5,000 ماسة', 'Buy for 5,000 diamonds')
                          : dedaText('شراء بعد التحقق', 'Purchase after verification'),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}

'''

def replace_once(source, old, new, where):
    if source.count(old) != 1:
        raise ValueError("SAFE_STOP: " + where + " anchor expected once, got " +
                         str(source.count(old)))
    return source.replace(old, new, 1)

def apply(source: str) -> str:
    for flag in ("// DEDA_INTAKADHA_POINT16_CLIENT_CALLABLE_GATEWAY_CLOSED_BY_DEFAULT",
                 "// DEDA_INTAKADHA_POINT15_SERVER_VERIFIED_OWNED_IDENTIFIERS_2026_10_19",
                 "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19"):
        if source.count(flag) != 1:
            raise ValueError("SAFE_STOP: missing verified stage " + flag)
    if MARKER in source:
        if source.count(MARKER) != 1 or "DedaPoint17ShopCardAction(" not in source:
            raise ValueError("SAFE_STOP: altered partial point17")
        return source
    if source.count(ACCOUNT) != 1 or source.count(ACCOUNT_END) != 1 or \
            source.count(SHOP) != 1 or source.count(SHOP_END) != 1:
        raise ValueError("SAFE_STOP: exact account and store class boundaries changed")
    a, b = source.index(ACCOUNT), source.index(ACCOUNT_END)
    account = source[a:b]
    account = replace_once(account, OLD_ACCOUNT_PAID,
                           "", "move paid card panel out of account")
    account = replace_once(account, BLUE, OWNED_BELOW_BLUE,
                           "show verified owned IDs beneath blue card")
    account = replace_once(account, OLD_NOTE, "", "remove duplicate old note")
    account = replace_once(account,
                           "padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),",
                           "padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),",
                           "compact blue ID card")
    if account.count("DedaPoint15OwnedIdentifierPanel(") != 1 or \
            "DedaPoint14VerifiedAccountPanel(" in account or \
            "DedaPreferences.setAccountType(type)" not in account:
        raise ValueError("SAFE_STOP: account layout or type selector regressed")
    source = source[:a] + account + source[b:]
    a, b = source.index(SHOP), source.index(SHOP_END)
    store = source[a:b]
    store = replace_once(store, SHOP,
                         SHOP + "\n" + SHOP_LIFECYCLE,
                         "store ownership refresh")
    store = replace_once(store, CARD_TAIL, NEW_CARD_TAIL,
                         "action under four existing 50dp cards")
    store = replace_once(store,
        "'مرشح غير متحقق من توفره — لا شراء ولا تفعيل',",
        "'السعر 10,000 ماسة — الشراء بعد تحقق الخادم من التوفر',",
        "all candidate identifier prices")
    store = replace_once(store,
        "'Unverified candidate — purchasing and activation disabled',",
        "'10,000 diamonds per ID — checkout awaits verified availability',",
        "english 10000 price")
    source = source[:a] + store + source[b:]
    source = replace_once(source, ACCOUNT, NEW_ACTIONS + ACCOUNT,
                          "inject stage17 secure cosmetic actions")
    if "defaultValue: false" not in source or \
            "DEDA_PREMIUM_IDS_SERVER_LIVE" not in source or \
            "DedaPoint15OwnedIdsBridge.grantReservedRemote = null;" not in source:
        raise ValueError("SAFE_STOP: original server gates missing")
    if "DedaBackend.claimDiamondGift(" not in source or \
            "_buildFixedDriverArrow(navigationArrowAngle)" not in source:
        raise ValueError("SAFE_STOP: gifts or maps missing")
    return source

if __name__ == "__main__":
    original = MAIN.read_text(encoding="utf-8")
    result = apply(original)
    if result != original:
        MAIN.write_text(result, encoding="utf-8")
    print("PASS: sapphire-only edit, verified owned IDs below, paid cards in store")
    print("PASS: cards 5000 each, candidate IDs 10000; real spending still gated")
