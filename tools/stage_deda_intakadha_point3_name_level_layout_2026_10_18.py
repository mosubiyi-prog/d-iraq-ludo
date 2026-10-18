#!/usr/bin/env python3
"""DEDA «إنت كدها», point 3/16: optical position only, after approved point 2.

Run on reconstructed lib/main.dart AFTER:
  - tools/stage_deda_three_royal_backgrounds_2026_10_18.py
  - tools/stage_deda_intakadha_point2_remove_member_2026_10_18.py
and BEFORE dart format, in a future approved combined private QA build.
No release, APK, backend, inventory, wallet, level computation or persisted state changes.
Refuse unfamiliar source instead of silently reformatting the card.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
START = "  Widget _profileHeroCard() {"
END = "  Widget _avatar(int frameStyle, double size) {"
POINT2 = "// DEDA_INTAKADHA_POINT2_MEMBER_CAPTION_REMOVED_2026_10_18"
MARKER = "// DEDA_INTAKADHA_POINT3_TIGHT_HERO_LEVEL_LAYOUT_2026_10_18"

# Before point 2: hero footer includes community row. Point 2 already
# removed that 6px margin, row and icon. Point 3 redistributes interior
# spacing without growing the card (avatar/name gap -6, level gap +12,
# bottom inset -6 => net 0). 51px equipped badge is untouched and taller
# than the slimmed golden level pill.
REPLACEMENTS = (
    (
        "                  compact ? 12 : 17,\n"
        "                  16,\n"
        "                ),\n"
        "                child: Column(",
        "                  compact ? 12 : 17,\n"
        "                  10,\n"
        "                ),\n"
        "                child: Column(",
        "decrease only hero's bottom inset by 6 px",
    ),
    (
        "                    ),\n"
        "                    const SizedBox(height: 10),\n"
        "                    ConstrainedBox(",
        "                    ),\n"
        "                    " + MARKER + "\n"
        "                    const SizedBox(height: 4),\n"
        "                    ConstrainedBox(",
        "raise NAME and original ID row by 6 px without scaling the portrait",
    ),
    (
        "                    ),\n"
        "                    const SizedBox(height: 12),\n"
        "                    Wrap(",
        "                    ),\n"
        "                    const SizedBox(height: 24),\n"
        "                    Wrap(",
        "lower equipped level/badge row 6 px relative to original positions",
    ),
    (
        "                            return Container(\n"
        "                              padding: const EdgeInsets.symmetric(\n"
        "                                horizontal: 15,\n"
        "                                vertical: 10,\n"
        "                              ),",
        "                            return Container(\n"
        "                              padding: const EdgeInsets.symmetric(\n"
        "                                horizontal: 15,\n"
        "                                vertical: 6,\n"
        "                              ),",
        "make only golden LEVEL pill 8 px shorter; unchanged badge and level text",
    ),
)
PROTECTED = (
    "DedaPreferences.userName",
    "_avatar(frameStyle, avatarSize)",
    "onTap: _copyDedaId",
    "DedaSocialProgressWallet.xpNotifier",
    "DedaSocialProgressWallet.levelForXp(",
    "'مستوى ذهبي $level'",
    "'Gold level $level'",
    "DedaStyleInventory.activeBadgeNotifier",
    "DedaBadgeAsset(id: badgeId, size: 42)",
    "width: 51",
    "height: 51",
)

def apply(source: str) -> str:
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP: missing or duplicate hero/portrait anchors")
    i = source.index(START)
    j = source.index(END, i)
    hero = source[i:j]
    if hero.count(POINT2) != 1 or "عضو في مجتمع DEDA" in hero:
        raise ValueError("SAFE_STOP: point 2 must already be applied to same rebuilt hero")
    if MARKER in hero:
        if hero.count(MARKER) != 1 or any(old in hero for old, _, _ in REPLACEMENTS):
            raise ValueError("SAFE_STOP: inconsistent point3 status; do not modify")
        return source
    for name in PROTECTED:
        if hero.count(name) != 1:
            raise ValueError("SAFE_STOP: protected element missing/ambiguous: " + name)
    original = hero
    for old, new, description in REPLACEMENTS:
        if hero.count(old) != 1:
            raise ValueError("SAFE_STOP: expected exactly one layout anchor: " + description)
        hero = hero.replace(old, new, 1)
    for name in PROTECTED:
        if hero.count(name) != original.count(name):
            raise ValueError("SAFE_STOP: protected profile element modified: " + name)
    if hero.count(MARKER) != 1:
        raise ValueError("SAFE_STOP: point3 marker not present exactly once")
    # Prove text edits are restricted to the four white-listed layout substitutions.
    rebuilt = hero
    for old, new, _ in reversed(REPLACEMENTS):
        rebuilt = rebuilt.replace(new, old, 1)
    if rebuilt != original:
        raise ValueError("SAFE_STOP: unauthorized layout modifications")
    return source[:i] + hero + source[j:]

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart unavailable")
    original = MAIN.read_text(encoding="utf-8")
    try:
        changed = apply(original)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if changed != original:
        MAIN.write_text(changed, encoding="utf-8")
        print("PASS: point3 raise name 6px; shift level row 6px lower; slim pill 8px")
    else:
        print("PASS: point3 already applied, safe repeat")
    print("PASS: no increased card vertical budget, badge/portrait/level logic untouched")
