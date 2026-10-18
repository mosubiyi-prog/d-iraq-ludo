#!/usr/bin/env python3
"""DEDA «إنت كدها» stage 2/16 — remove ONLY the member-of-community caption from profile hero.

Run AFTER tools/stage_deda_three_royal_backgrounds_2026_10_18.py, BEFORE dart format,
on the rebuilt lib/main.dart in an isolated development workflow. Source-only; no APK,
Firebase, purchased frame, user account, profile setting, level or wallet mutation.
Fail closed if the expected original caption does not match byte-for-byte.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_INTAKADHA_POINT2_MEMBER_CAPTION_REMOVED_2026_10_18"
START = "  Widget _profileHeroCard() {"
END = "  Widget _avatar(int frameStyle, double size) {"
OLD_NOTICE = "                    const SizedBox(height: 6),\n                    Row(\n                      mainAxisAlignment: MainAxisAlignment.center,\n                      mainAxisSize: MainAxisSize.min,\n                      children: <Widget>[\n                        const Icon(\n                          Icons.people_alt_outlined,\n                          color: Color(0xFFE6DBF4),\n                          size: 16,\n                        ),\n                        const SizedBox(width: 6),\n                        Flexible(\n                          child: Text(\n                            dedaText(\n                              'عضو في مجتمع DEDA',\n                              'Member of the DEDA community',\n                            ),\n                            maxLines: 1,\n                            overflow: TextOverflow.ellipsis,\n                            style: const TextStyle(\n                              color: Color(0xFFE9DFF9),\n                              fontSize: 13,\n                              fontWeight: FontWeight.w700,\n                            ),\n                          ),\n                        ),\n                      ],\n                    ),\n"
NEW_NOTICE = "                    " + MARKER + "\n"
PRESERVE = (
    "DedaPreferences.userName",
    "onTap: _copyDedaId",
    "DedaSocialProgressWallet.xpNotifier",
    "DedaSocialProgressWallet.levelForXp(",
    "DedaStyleInventory.activeBadgeNotifier",
    "DedaBadgeAsset(id: badgeId, size: 42)",
    "مستوى ذهبي $level",
    "_avatar(frameStyle, avatarSize)",
)

def apply(source: str) -> str:
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("SAFE_STOP: expected exactly one profile hero or avatar anchor")
    i = source.index(START)
    j = source.index(END, i)
    hero = source[i:j]
    if MARKER in hero:
        if OLD_NOTICE in hero or "عضو في مجتمع DEDA" in hero or "Member of the DEDA community" in hero:
            raise ValueError("SAFE_STOP: stage marker present but removed caption still exists")
        if hero.count(MARKER) != 1:
            raise ValueError("SAFE_STOP: duplicate point 2 marker")
        return source
    if hero.count(OLD_NOTICE) != 1:
        raise ValueError("SAFE_STOP: original profile-only community caption did not match exactly")
    for item in PRESERVE:
        if item not in hero:
            raise ValueError("SAFE_STOP: protected profile element missing: " + item)
    updated = hero.replace(OLD_NOTICE, NEW_NOTICE, 1)
    if updated.count(MARKER) != 1:
        raise ValueError("SAFE_STOP: point 2 marker missing/duplicated")
    for item in PRESERVE:
        if hero.count(item) != updated.count(item):
            raise ValueError("SAFE_STOP: protected profile element changed: " + item)
    result = source[:i] + updated + source[j:]
    if result.replace(NEW_NOTICE, OLD_NOTICE, 1) != source:
        raise ValueError("SAFE_STOP: unrelated code changed")
    return result

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: rebuilt lib/main.dart unavailable")
    original = MAIN.read_text(encoding="utf-8")
    try:
        edited = apply(original)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if edited != original:
        MAIN.write_text(edited, encoding="utf-8")
        print("PASS: removed only profile community caption, people icon and its spacing")
    else:
        print("PASS: point 2 already applied; no duplicate edit")
    print("PASS: profile name, ID/copy, avatar/frame, badge, level and wallets untouched")
