#!/usr/bin/env python3
"""«إنت كدها» stage 7: add four free previews beneath *account ID management*.

Run after complete 100356 reconstruction and approved stages 2 through 6.
No source edits until private combined QA. Preview selection stays ephemeral.
Never assume ID cosmetics are owned, available for sale, or activated.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
ACCOUNT_END = "class DedaDiamondsState {"
MARKER = "// DEDA_INTAKADHA_POINT7_FOUR_CARDS_UNDER_ID_MANAGEMENT_2026_10_18"
POINT6 = "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18"
POINT5 = "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18"
ORIGINAL_BUTTON = "            child: Text(dedaText('التفعيل بعد التحقق', 'Activate after verification')),\n          ),"
NEW_BUTTON = "            child: Text(dedaText('التفعيل بعد التحقق', 'Activate after verification')),\n          ),\n          const SizedBox(height: 13),\n          DedaPremiumIdCardsManagementPanel(\n            identifier: originalId,\n            // NO entitlement is inferred from the preview. Actual ownership\n            // validation and activation belong to stages 12, 14 and 15.\n            serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},\n            verifiedActiveColor: null,\n            onActivateVerified: null,\n          ),"
WIDGET = r'''// DEDA_INTAKADHA_POINT7_FOUR_CARDS_UNDER_ID_MANAGEMENT_2026_10_18
// Cosmetics previews ONLY. A local preview is NEVER proof of ownership.
// The caller must pass server-verified owned styles and a safe activation
// handler in a later approved stage. Empty set + null handler = NO activation.
class DedaPremiumIdCardsManagementPanel extends StatefulWidget {
  final String identifier;
  final Set<DedaPremiumIdCardColor> serverVerifiedOwnedColors;
  final DedaPremiumIdCardColor? verifiedActiveColor;
  final ValueChanged<DedaPremiumIdCardColor>? onActivateVerified;

  const DedaPremiumIdCardsManagementPanel({
    super.key,
    required this.identifier,
    required this.serverVerifiedOwnedColors,
    required this.verifiedActiveColor,
    required this.onActivateVerified,
  });

  @override
  State<DedaPremiumIdCardsManagementPanel> createState() =>
      _DedaPremiumIdCardsManagementPanelState();
}

class _DedaPremiumIdCardsManagementPanelState
    extends State<DedaPremiumIdCardsManagementPanel> {
  DedaPremiumIdCardColor _preview = DedaPremiumIdCardColor.gold;
  static const int priceDiamonds = 5000;

  String _name(DedaPremiumIdCardColor value) {
    switch (value) {
      case DedaPremiumIdCardColor.gold:
        return dedaText('ذهبي', 'Gold');
      case DedaPremiumIdCardColor.diamond:
        return dedaText('ماسي', 'Diamond');
      case DedaPremiumIdCardColor.royal:
        return dedaText('ملكي', 'Royal');
      case DedaPremiumIdCardColor.pink:
        return dedaText('وردي', 'Pink');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('deda_intakadha_point7_card_store_under_id_management'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          dedaText('بطاقات الآيدي الفخمة', 'Premium ID cards'),
          style: const TextStyle(
            color: Color(0xFFFFE5AC),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dedaText(
            'اضغط على أي بطاقة لمعاينتها مجانًا. سعر التصميم الواحد 5,000 ماسة، وهو منفصل عن سعر المعرّف.',
            'Tap a card for a free preview. Each cosmetic style costs 5,000 diamonds, separately from the identifier.',
          ),
          style: const TextStyle(
            color: Color(0xFFD3DFEB),
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 9),
        for (final style in DedaPremiumIdCardColor.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Builder(
              builder: (context) {
                final owned = widget.serverVerifiedOwnedColors.contains(style);
                final active = owned && widget.verifiedActiveColor == style;
                final selected = _preview == style;
                final canUse = owned &&
                    !active &&
                    widget.onActivateVerified != null;
                return Container(
                  key: ValueKey<String>('deda_intakadha_point7_card_' + style.name),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF344C67)
                        : const Color(0xFF14283F),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFD78F)
                          : const Color(0xFF5A6B7D),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DedaPremiumIdCard(
                        key: ValueKey<String>('deda_intakadha_point7_preview_' + style.name),
                        identifier: widget.identifier,
                        color: style,
                        height: 50,
                        onTap: () => setState(() => _preview = style),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _name(style),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFFE5B5),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            selected
                                ? dedaText('معاينة مجانية ✓', 'Free preview ✓')
                                : dedaText('اضغط للمعاينة', 'Tap to preview'),
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFFB1F3CE)
                                  : const Color(0xFFC6D5E5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              active
                                  ? dedaText('مستخدمة حاليًا', 'Currently in use')
                                  : owned
                                      ? dedaText('مملوكة ✓', 'Owned ✓')
                                      : dedaText('بانتظار إثبات الملكية', 'Ownership not verified'),
                              style: const TextStyle(
                                color: Color(0xFFD5E1EC),
                                fontSize: 10,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            owned
                                ? dedaText('مملوكة', 'Owned')
                                : dedaText('5,000 ماسة', '5,000 diamonds'),
                            style: const TextStyle(
                              color: Color(0xFFFFD38D),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          key: ValueKey<String>('deda_intakadha_point7_use_' + style.name),
                          onPressed: canUse
                              ? () => widget.onActivateVerified!(style)
                              : null,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFCEB17B)),
                            foregroundColor: const Color(0xFFFFE3AD),
                            disabledForegroundColor: const Color(0xFF8F9EB0),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(
                            active
                                ? dedaText('مستخدمة', 'In use')
                                : owned
                                    ? dedaText('استخدام', 'Use')
                                    : dedaText('الشراء بعد التحقق', 'Purchase after verification'),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

'''

def apply(source: str) -> str:
    if source.count(ACCOUNT) != 1 or source.count(ACCOUNT_END) != 1:
        raise ValueError("SAFE_STOP: original account class boundaries changed")
    if source.count(POINT5) != 1 or source.count(POINT6) != 1:
        raise ValueError("SAFE_STOP: paid ID art / protected profile slot not ready")
    if source.count("deda_point7_inline_id_manager") != 1:
        raise ValueError("SAFE_STOP: 100342 inline ID manager missing or duplicated")
    a = source.index(ACCOUNT)
    b = source.index(ACCOUNT_END, a)
    account = source[a:b]
    if MARKER in source:
        if source.count(MARKER) != 1 or WIDGET not in source or account.count(NEW_BUTTON) != 1:
            raise ValueError("SAFE_STOP: partial or non-identical stage7")
        if account.count(ORIGINAL_BUTTON) != 0:
            raise ValueError("SAFE_STOP: old account ID manager button not replaced")
        return source
    if "class DedaPremiumIdCardsManagementPanel extends" in source:
        raise ValueError("SAFE_STOP: conflicting ID card management component")
    if account.count(ORIGINAL_BUTTON) != 1:
        raise ValueError("SAFE_STOP: expected ONE unchanged locked activation button")
    for key in (
        "onPressed: null",
        "deda_point7_activate_requires_verified_ownership",
        "DedaBackend.personalShareIdForPhone(DedaPreferences.phone)",
        "deda_point7_switch_opens_id_manager",
        "deda_point7_edit_identifier_action",
        "DedaPreferences.setAccountType(type)",
    ):
        if key not in account:
            raise ValueError("SAFE_STOP: protected account path missing: " + key)
    updated = account.replace(ORIGINAL_BUTTON, NEW_BUTTON, 1)
    if updated.replace(NEW_BUTTON, ORIGINAL_BUTTON, 1) != account:
        raise ValueError("SAFE_STOP: extra account changes")
    output = source[:a] + updated + source[b:]
    output = output.replace(ACCOUNT, WIDGET + ACCOUNT, 1)
    if output.replace(WIDGET, "", 1).replace(NEW_BUTTON, ORIGINAL_BUTTON, 1) != source:
        raise ValueError("SAFE_STOP: non-account or wallet code touched")
    return output

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart missing")
    source = MAIN.read_text(encoding="utf-8")
    try:
        updated = apply(source)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if updated != source:
        MAIN.write_text(updated, encoding="utf-8")
        print("PASS: four 50px live-ID decorative previews added under Account > Manage identifiers")
    else:
        print("PASS: stage7 already applied")
    print("PASS: free previews only; 5000 diamond display, no buying, no owned styles, no activation")
