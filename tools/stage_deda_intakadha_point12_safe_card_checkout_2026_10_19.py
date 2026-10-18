#!/usr/bin/env python3
"""DEDA point12: confirmation + atomic receipt UI only; no real charges.

Historical wallet combines SharedPreferences and Firebase gifted/personal funds.
Old DedaDiamondsWallet.spend() followed by addOwned() is non-atomic.
Therefore checkout stays DISABLED until an audited authenticated server backend
atomically commits a 5000-diamond deduction and permanent card ownership.
"""
import ast
from pathlib import Path

MAIN = Path("lib/main.dart")
STAGE7 = Path(__file__).resolve().parent / "stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py"
POINT11 = "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
ACCOUNT_END = "class DedaDiamondsState {"
MARKER = "// DEDA_INTAKADHA_POINT12_SAFE_CARD_CHECKOUT_UI_2026_10_19"
HEADER = r'''// DEDA_INTAKADHA_POINT12_SAFE_CARD_CHECKOUT_UI_2026_10_19
// Receipt and verified ownership MUST come from the same authenticated
// server-atomic checkout transaction; never charge locally then save later.
class DedaIdCardPurchaseReceipt {
  final String transactionId;
  final DedaPremiumIdCardColor color;
  final int diamondsCharged;
  final bool serverConfirmed;
  final bool alreadyOwned;
  const DedaIdCardPurchaseReceipt({
    required this.transactionId,
    required this.color,
    required this.diamondsCharged,
    required this.serverConfirmed,
    required this.alreadyOwned,
  });
}

typedef DedaIdCardPurchaseGateway = Future<DedaIdCardPurchaseReceipt> Function(
  DedaPremiumIdCardColor color,
  String requestId,
);
typedef DedaIdCardOwnedRefresh = Future<Set<DedaPremiumIdCardColor>> Function();

'''
TRANSFORMATIONS = [["  final ValueChanged<DedaPremiumIdCardColor>? onActivateVerified;\n","  final ValueChanged<DedaPremiumIdCardColor>? onActivateVerified;\n  final DedaIdCardPurchaseGateway? onPurchaseVerified;\n  final DedaIdCardOwnedRefresh? refreshVerifiedOwnership;\n"],["    required this.onActivateVerified,\n","    required this.onActivateVerified,\n    this.onPurchaseVerified,\n    this.refreshVerifiedOwnership,\n"],["  static const int priceDiamonds = 5000;\n","  static const int priceDiamonds = 5000;\n  final Set<DedaPremiumIdCardColor> _freshOwned = <DedaPremiumIdCardColor>{};\n  final Map<DedaPremiumIdCardColor, String> _requestIds =\n      <DedaPremiumIdCardColor, String>{};\n  bool _purchaseBusy = false;\n\n  Future<void> _confirmPurchase(DedaPremiumIdCardColor style) async {\n    // Preview never charges. Checkout stays disabled without trusted backend.\n    if (_purchaseBusy || _freshOwned.contains(style) ||\n        widget.serverVerifiedOwnedColors.contains(style) ||\n        widget.onPurchaseVerified == null ||\n        widget.refreshVerifiedOwnership == null) return;\n    final confirmed = await showDialog<bool>(\n      context: context,\n      builder: (dialogContext) => AlertDialog(\n        title: Text(dedaText('تأكيد شراء بطاقة الآيدي', 'Confirm ID card purchase')),\n        content: Text(dedaText(\n          'شراء تصميم ' + _name(style) +\n              ' مقابل 5,000 ماسة؟ سعر البطاقة منفصل عن سعر المعرّف.',\n          'Buy the ' + _name(style) +\n              ' ID card for 5,000 diamonds? The identifier is priced separately.',\n        )),\n        actions: <Widget>[\n          TextButton(\n            key: const Key('deda_point12_cancel_purchase'),\n            onPressed: () => Navigator.pop(dialogContext, false),\n            child: Text(dedaText('إلغاء', 'Cancel')),\n          ),\n          FilledButton(\n            key: const Key('deda_point12_confirm_purchase'),\n            onPressed: () => Navigator.pop(dialogContext, true),\n            child: Text(dedaText('تأكيد 5,000 ماسة', 'Confirm 5,000 diamonds')),\n          ),\n        ],\n      ),\n    );\n    if (confirmed != true || !mounted || _purchaseBusy ||\n        _freshOwned.contains(style) ||\n        widget.serverVerifiedOwnedColors.contains(style) ||\n        widget.onPurchaseVerified == null ||\n        widget.refreshVerifiedOwnership == null) return;\n\n    setState(() => _purchaseBusy = true);\n    final requestId = _requestIds.putIfAbsent(\n      style,\n      () => DateTime.now().toUtc().microsecondsSinceEpoch.toString() +\n          '-' + style.name,\n    );\n    String message;\n    try {\n      final receipt = await widget.onPurchaseVerified!(style, requestId);\n      if (!receipt.serverConfirmed ||\n          receipt.transactionId.trim().isEmpty ||\n          receipt.color != style ||\n          (receipt.alreadyOwned && receipt.diamondsCharged != 0) ||\n          (!receipt.alreadyOwned && receipt.diamondsCharged != priceDiamonds)) {\n        throw StateError('deda-id-card-invalid-server-receipt');\n      }\n      // Even a successful receipt alone is NOT a local ownership grant.\n      final verified = await widget.refreshVerifiedOwnership!();\n      if (!verified.contains(style)) {\n        throw StateError('deda-id-card-entitlement-refetch-failed');\n      }\n      if (!mounted) return;\n      setState(() => _freshOwned.addAll(verified));\n      message = dedaText(\n        'تم تأكيد ملكية بطاقة ' + _name(style) + '.',\n        'Ownership confirmed for the ' + _name(style) + ' design.',\n      );\n    } catch (_) {\n      message = dedaText(\n        'تعذّر التحقق من الشراء أو الملكية. افحص المشتريات قبل إعادة المحاولة.',\n        'Purchase or ownership not verified. Check purchases before retrying.',\n      );\n    } finally {\n      if (mounted) setState(() => _purchaseBusy = false);\n    }\n    if (mounted) {\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(content: Text(message, textAlign: TextAlign.center)),\n      );\n    }\n  }\n\n"],["final owned = widget.serverVerifiedOwnedColors.contains(style);","final owned = widget.serverVerifiedOwnedColors.contains(style) || _freshOwned.contains(style);"],["                final canUse = owned &&\n","                final canPurchase = !owned && !_purchaseBusy &&\n                    widget.onPurchaseVerified != null &&\n                    widget.refreshVerifiedOwnership != null;\n                final canUse = owned &&\n"],["                      const SizedBox(height: 5),\n                      SizedBox(\n                        height: 32,\n                        child: OutlinedButton(","                      const SizedBox(height: 5),\n                      SizedBox(\n                        height: 32,\n                        child: OutlinedButton(\n                          key: ValueKey<String>('deda_point12_buy_' + style.name),\n                          onPressed: canPurchase\n                              ? () => _confirmPurchase(style)\n                              : null,\n                          style: OutlinedButton.styleFrom(\n                            foregroundColor: const Color(0xFFFFE6AD),\n                            disabledForegroundColor: const Color(0xFF98A5B5),\n                            side: const BorderSide(color: Color(0xFFE2C17E)),\n                          ),\n                          child: Text(\n                            owned\n                                ? dedaText('مملوكة ✓', 'Owned ✓')\n                                : _purchaseBusy\n                                    ? dedaText('انتظر...', 'Please wait...')\n                                    : canPurchase\n                                        ? dedaText('شراء بـ5,000 ماسة', 'Buy for 5,000 diamonds')\n                                        : dedaText('الشراء بعد التحقق', 'Purchase after verification'),\n                            style: const TextStyle(fontSize: 11),\n                          ),\n                        ),\n                      ),\n                      const SizedBox(height: 5),\n                      SizedBox(\n                        height: 32,\n                        child: OutlinedButton("]]
CALL_OLD = "            onActivateVerified: null,\n"
CALL_NEW = "            onActivateVerified: null,\n            onPurchaseVerified: null,\n            refreshVerifiedOwnership: null,\n"

def original_widget():
    tree = ast.parse(STAGE7.read_text(encoding="utf-8"))
    found = [node.value.value for node in tree.body if isinstance(node, ast.Assign)
             and any(isinstance(t, ast.Name) and t.id == "WIDGET" for t in node.targets)
             and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)]
    if len(found) != 1:
        raise ValueError("SAFE_STOP: stage7 premium ID panel unavailable")
    return found[0]

def upgraded_widget():
    old = original_widget()
    new = old
    for before, after in TRANSFORMATIONS:
        if new.count(before) != 1:
            raise ValueError("SAFE_STOP: stage7 card source changed: " + before[:65])
        new = new.replace(before, after, 1)
    reversed_widget = new
    for before, after in reversed(TRANSFORMATIONS):
        if reversed_widget.count(after) != 1:
            raise ValueError("SAFE_STOP: ambiguous checkout widget patch")
        reversed_widget = reversed_widget.replace(after, before, 1)
    if reversed_widget != old:
        raise ValueError("SAFE_STOP: checkout patched unrelated widget")
    return HEADER + new

def apply(source):
    if source.count(POINT11) != 1 or source.count(ACCOUNT) != 1 or source.count(ACCOUNT_END) != 1:
        raise ValueError("SAFE_STOP: prior stage11 / account boundaries missing")
    old, new = original_widget(), upgraded_widget()
    if MARKER in source:
        if source.count(MARKER) != 1 or new not in source or source.count(CALL_NEW) != 1 or old in source:
            raise ValueError("SAFE_STOP: incomplete or changed stage12")
        return source
    if source.count(old) != 1 or source.count(CALL_OLD) != 1:
        raise ValueError("SAFE_STOP: expected one original premium ID panel and locked account call")
    a, b = source.index(ACCOUNT), source.index(ACCOUNT_END)
    account = source[a:b]
    if account.count("serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},") != 1 or             account.count(CALL_OLD) != 1:
        raise ValueError("SAFE_STOP: original trust boundary for panel missing")
    output = source.replace(old, new, 1).replace(CALL_OLD, CALL_NEW, 1)
    if output.replace(new, old, 1).replace(CALL_NEW, CALL_OLD, 1) != source:
        raise ValueError("SAFE_STOP: unrelated app/wallet/source modifications")
    if output.count("onPurchaseVerified: null,") != 1 or             output.count("refreshVerifiedOwnership: null,") != 1:
        raise ValueError("SAFE_STOP: unauthorized real checkout activation")
    return output

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart missing")
    previous = MAIN.read_text(encoding="utf-8")
    try:
        new = apply(previous)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if new != previous:
        MAIN.write_text(new, encoding="utf-8")
        print("PASS: 5000-diamond checkout confirmation and idempotent request guard staged")
    else:
        print("PASS: stage12 already present and identical")
    print("PASS: money deductions DISABLED until trusted atomic server+entitlement backend")
