#!/usr/bin/env python3
"""«إنت كدها» point 6 of 16: connect protected ID slot to profile UI.

Source-only stage after exact 100356 reconstruction and points 2,3,4,5.
NO automatic paid-card activation: verifiedOwnedColor:null until later
ownership and activation steps. Original phone ID and copy callback remain.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
START = "  Widget _profileHeroCard() {"
END = "  Widget _avatar(int frameStyle, double size) {"
CLASS = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
POINT4 = "// DEDA_INTAKADHA_POINT4_RECTANGULAR_ID_50PX_2026_10_18"
POINT5 = "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18"
MARKER = "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18"
WIDGET = r'''// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18
// Display logic only. Do not treat a selected color as proof of purchase.
// [verifiedOwnedColor] MUST come from later server-verified ownership;
// null preserves the normal ID and does not grant any of four paid cards.
class DedaProfileVerifiedIdCardSlot extends StatelessWidget {
  final String identifier;
  final DedaPremiumIdCardColor? verifiedOwnedColor;
  final VoidCallback onCopy;
  final double width;
  final bool compact;

  const DedaProfileVerifiedIdCardSlot({
    super.key,
    required this.identifier,
    required this.verifiedOwnedColor,
    required this.onCopy,
    required this.width,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final selected = verifiedOwnedColor;
    return SizedBox(
      width: width,
      height: 50,
      child: selected == null
          ? Material(
              color: const Color(0x2BFFFFFF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onCopy,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: width,
                  height: 50,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0x88D7C8F4),
                      width: 1,
                    ),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            identifier,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 15.0 : 17.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.copy_rounded,
                          color: Color(0xFFEEE7FD),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                DedaPremiumIdCard(
                  identifier: identifier,
                  color: selected,
                  onTap: onCopy,
                  height: 50,
                ),
                // Card itself handles taps, preserving the real copy action.
                // Small cue above the right-side jewel, not over the ID text.
                const PositionedDirectional(
                  top: 6,
                  end: 9,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.copy_rounded,
                      size: 11,
                      color: Color(0xDFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

'''
LEGACY_ID = r'''                    Material(
                      color: const Color(0x2BFFFFFF),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _copyDedaId,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                          height: 50,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0x88D7C8F4),
                              width: 1,
                            ),
                          ),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compact ? 15.0 : 17.0,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.copy_rounded,
                                  color: Color(0xFFEEE7FD),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
'''
NEW_ID = '''                    DedaProfileVerifiedIdCardSlot(
                      identifier: id,
                      // No user owns paid artwork until verified; stages 7/12/15
                      // will supply trusted ownership and a selected style.
                      verifiedOwnedColor: null,
                      onCopy: _copyDedaId,
                      width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                      compact: compact,
                    ),
'''
PRESERVE = (
    "final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;",
    "DedaPreferences.userName",
    "DedaProfileAppearanceState.frameNotifier",
    "DedaSocialProgressWallet.xpNotifier",
    "DedaStyleInventory.activeBadgeNotifier",
    "DedaBadgeAsset(id: badgeId, size: 42)",
    "'مستوى ذهبي $level'",
    "DedaRoyalBackgroundArtwork",
)

def apply(source: str) -> str:
    if source.count(START) != 1 or source.count(END) != 1 or source.count(CLASS) != 1:
        raise ValueError("SAFE_STOP: ambiguous rebuilt profile hero/class")
    if source.count(POINT4) != 1 or source.count(POINT5) != 1:
        raise ValueError("SAFE_STOP: stage4 geometry/stage5 foil widget missing")
    i = source.index(START)
    j = source.index(END, i)
    hero = source[i:j]
    if MARKER in source:
        if source.count(MARKER) != 1 or WIDGET not in source or hero.count(NEW_ID) != 1 or LEGACY_ID in hero:
            raise ValueError("SAFE_STOP: partial or conflicting point6 application")
        return source
    if "class DedaProfileVerifiedIdCardSlot extends" in source:
        raise ValueError("SAFE_STOP: ID slot class already exists with different code")
    if hero.count(LEGACY_ID) != 1:
        raise ValueError("SAFE_STOP: original point4 ID chip unexpectedly differs")
    if "                    const SizedBox(height: 2),\n" + LEGACY_ID not in hero:
        raise ValueError("SAFE_STOP: 50px slot not exactly below profile name")
    if "                    const SizedBox(height: 14),\n                    Wrap(" not in hero:
        raise ValueError("SAFE_STOP: level row spacing from stage4 missing")
    for token in PRESERVE:
        if token not in source:
            raise ValueError("SAFE_STOP: protected 100356 behavior missing: " + token)
    updated_hero = hero.replace(LEGACY_ID, NEW_ID, 1)
    if updated_hero.replace(NEW_ID, LEGACY_ID, 1) != hero:
        raise ValueError("SAFE_STOP: unintended profile source edits")
    new_source = source[:i] + updated_hero + source[j:]
    if new_source.count(CLASS) != 1:
        raise ValueError("SAFE_STOP: duplicate profile class during integration")
    new_source = new_source.replace(CLASS, WIDGET + CLASS, 1)
    if new_source.replace(WIDGET, "", 1).replace(NEW_ID, LEGACY_ID, 1) != source:
        raise ValueError("SAFE_STOP: changes outside protected point6 scope")
    return new_source

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: rebuilt lib/main.dart is unavailable")
    old = MAIN.read_text(encoding="utf-8")
    try:
        new = apply(old)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if new != old:
        MAIN.write_text(new, encoding="utf-8")
        print("PASS: 50px ID slot wired under name; original ID and tap-to-copy preserved")
    else:
        print("PASS: point6 already applied; no duplicate slot")
    print("PASS: no paid variant active by default; ownership integration is a later point")
