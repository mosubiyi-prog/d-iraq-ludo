#!/usr/bin/env python3
"""DEDA «إنت كدها» — point 4/16, reserve exact rectangular ID-card geometry.

Apply on 100356-generated lib/main.dart only AFTER:
  (a) tools/stage_deda_three_royal_backgrounds_2026_10_18.py
  (b) tools/stage_deda_intakadha_point2_remove_member_2026_10_18.py
  (c) tools/stage_deda_intakadha_point3_name_level_layout_2026_10_18.py
before dart format in a later owner-approved composite private APK run.

This is geometry ONLY: no ID purchase, card artwork, inventory, ownership,
wallet, active-ID change, Firebase or publishing operations.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
START = "  Widget _profileHeroCard() {"
END = "  Widget _avatar(int frameStyle, double size) {"
POINT2 = "// DEDA_INTAKADHA_POINT2_MEMBER_CAPTION_REMOVED_2026_10_18"
POINT3 = "// DEDA_INTAKADHA_POINT3_TIGHT_HERO_LEVEL_LAYOUT_2026_10_18"
POINT4 = "// DEDA_INTAKADHA_POINT4_RECTANGULAR_ID_50PX_2026_10_18"

# Old account ID chip: naturally sized (~35px tall depending on text metrics).
# New ID preview slot: 50px high, 14px corner radius, responsive width <=320px.
# Reduce unused surrounding gaps by 5px and 10px to offset most of extra height;
# exact card height must still be visually verified on real Flutter device at QA.
REPLACEMENTS = (
    (
        "                    const SizedBox(height: 7),\n"
        "                    Material(",
        "                    " + POINT4 + "\n"
        "                    const SizedBox(height: 2),\n"
        "                    Material(",
        "ID top gap 7 -> 2, creating room under name",
        1,
    ),
    (
        "                      child: Container(\n"
        "                          constraints: const BoxConstraints(maxWidth: 320),\n"
        "                          padding: const EdgeInsets.symmetric(\n"
        "                            horizontal: 13,\n"
        "                            vertical: 7,\n"
        "                          ),",
        "                      child: Container(\n"
        "                          width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),\n"
        "                          height: 50,\n"
        "                          alignment: Alignment.center,\n"
        "                          padding: const EdgeInsets.symmetric(horizontal: 13),",
        "exact 50px-high responsive rectangle (no dynamic ID-dependent width)",
        1,
    ),
    (
        "                    const SizedBox(height: 24),\n"
        "                    Wrap(",
        "                    const SizedBox(height: 14),\n"
        "                    Wrap(",
        "level row gap 24 -> 14, compensating card's reserved height",
        1,
    ),
    (
        "borderRadius: BorderRadius.circular(28)",
        "borderRadius: BorderRadius.circular(14)",
        "all three rounded capsule corners become rectangle corners",
        3,
    ),
)
PRESERVE = (
    "DedaPreferences.userName",
    "DedaPreferences.profileBackgroundStyle",
    "_avatar(frameStyle, avatarSize)",
    "onTap: _copyDedaId",
    "fontSize: compact ? 15.0 : 17.0",
    "const Icon(\n                                  Icons.copy_rounded,",
    "DedaSocialProgressWallet.xpNotifier",
    "DedaSocialProgressWallet.levelForXp(",
    "'مستوى ذهبي $level'",
    "DedaStyleInventory.activeBadgeNotifier",
    "DedaBadgeAsset(id: badgeId, size: 42)",
)

def apply(source: str) -> str:
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP: missing or duplicate profile hero boundaries")
    i = source.index(START)
    j = source.index(END, i)
    before = source[i:j]
    if before.count(POINT2) != 1 or before.count(POINT3) != 1:
        raise ValueError("SAFE_STOP: points 2 and 3 must be applied first")
    if "عضو في مجتمع DEDA" in before or "Member of the DEDA community" in before:
        raise ValueError("SAFE_STOP: member caption unexpectedly restored")

    if POINT4 in before:
        if before.count(POINT4) != 1:
            raise ValueError("SAFE_STOP: duplicate point4 marker")
        if any(before.count(old) for old, _, _, _ in REPLACEMENTS):
            raise ValueError("SAFE_STOP: inconsistent partial point4 layout")
        return source

    for token in PRESERVE:
        if before.count(token) < 1:
            raise ValueError("SAFE_STOP: missing protected identifier/profile behavior: " + token)
    after = before
    for old, new, description, times in REPLACEMENTS:
        if after.count(old) != times:
            raise ValueError(
                f"SAFE_STOP: expected {times} exact occurrences for {description}, "
                f"found {after.count(old)}"
            )
        after = after.replace(old, new, times)
    for token in PRESERVE:
        if after.count(token) != before.count(token):
            raise ValueError("SAFE_STOP: protected identifier/profile behavior changed: " + token)
    if after.count(POINT4) != 1:
        raise ValueError("SAFE_STOP: rectangular ID marker missing")

    # Whitelist is literal: undo all substitutions and require perfect identity.
    reverted = after
    for old, new, _, times in reversed(REPLACEMENTS):
        if reverted.count(new) != times:
            raise ValueError("SAFE_STOP: ambiguous replacement region")
        reverted = reverted.replace(new, old, times)
    if reverted != before:
        raise ValueError("SAFE_STOP: scope or source changed beyond point4")
    return source[:i] + after + source[j:]

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart unavailable")
    original = MAIN.read_text(encoding="utf-8")
    try:
        updated = apply(original)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if updated != original:
        MAIN.write_text(updated, encoding="utf-8")
        print("PASS: reserved rectangular profile ID slot <=320px wide, exactly 50px high")
        print("PASS: 14px corners; surrounding gaps reduced; name, copy, level untouched")
    else:
        print("PASS: point4 already staged, no duplicate layout changes")
    print("PASS: no backend, diamond wallet, frame, inventory, ID purchase, or Play mutation")
