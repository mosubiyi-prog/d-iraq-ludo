#!/usr/bin/env python3
"""DEDA «إنت كدها» stage 8 of 16 — repurpose original Photos tile only.

After reconstructed 100356 + approved stages 2..7, swap the EMPTY purple
Photos card with "متجر المعرّفات", keeping its original grid location,
102dp accepted height, purple gradient, neighbor cards, data, and navigation untouched.
Stage9 builds store page; for now tapping opens an honest coming-soon notice.
Compact glyph/title layout applies ONLY to this store tile; all other
_featureCard callers render with the same defaults and dimensions as before.
"""
from pathlib import Path
import re

MAIN = Path("lib/main.dart")
STATE = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
END = "class DedaPublicProfilePreviewPage"
GRID = "  Widget _featureGrid() {"
CARD = "  Widget _featureCard({"
BIO = "  Widget _bioCard() {"
MARKER = "// DEDA_INTAKADHA_POINT8_PHOTOS_TILE_BECOMES_ID_SHOP_2026_10_18"
PREREQUISITES = (
    "// DEDA_PROFILE_STAGE_CARDS_FIX_100263",
    "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18",
    "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18",
    "// DEDA_INTAKADHA_POINT7_FOUR_CARDS_UNDER_ID_MANAGEMENT_2026_10_18",
)
OLD_TILE = "                icon: Icons.photo_library_rounded,\n                title: dedaText('الصور', 'Photos'),\n                subtitle: dedaText('قسم مستقل للصور لاحقًا', 'Dedicated photos area later'),\n                colors: const <Color>[Color(0xFF914BE1), Color(0xFF6530B7)],\n                onTap: () => _showPhase2Notice(\n                  'أبقينا قسم الصور بمكانه وسيتم تخصيص وظيفة مستقلة له عند حاجتنا لها.',\n                  'The Photos section stays in place and will receive its own dedicated function when needed.',\n                ),"
NEW_TILE = "                // DEDA_INTAKADHA_POINT8_PHOTOS_TILE_BECOMES_ID_SHOP_2026_10_18\n                icon: Icons.storefront_rounded,\n                title: dedaText('متجر المعرّفات', 'Identifier store'),\n                subtitle: dedaText('معرّفات مميزة', 'Premium identifiers'),\n                colors: const <Color>[Color(0xFF914BE1), Color(0xFF6530B7)],\n                compactContent: true,\n                onTap: () => _showPhase2Notice(\n                  'متجر المعرّفات قيد التجهيز. التصفح والشراء يتفعّلان بعد إكمال المتجر والتحقق من الملكية.',\n                  'The identifier store is being prepared. Browsing and purchases will open after the store and ownership checks are ready.',\n                ),"
METHOD_EDITS = (
    (
        r'''    required VoidCallback onTap,
  }) {''',
        r'''    required VoidCallback onTap,
    bool compactContent = false,
  }) {''',
        "Opt-in store-only compact mode, unchanged default for existing buttons",
    ),
    (
        r'''                width: 40,
                height: 40,''',
        r'''                width: compactContent ? 24 : 40,
                height: compactContent ? 24 : 40,''',
        "Store-only 24px icon circle, preserve accepted 100356 40px default",
    ),
    (
        r'''                child: Icon(icon, color: Colors.white, size: 23),''',
        r'''                child: Icon(icon, color: Colors.white, size: compactContent ? 18 : 23),''',
        "Store-only 18px glyph, preserve accepted 100356 23px default",
    ),
    (
        r'''              const SizedBox(width: 9),''',
        r'''              SizedBox(width: compactContent ? 3 : 9),''',
        "Store-only tight gap, preserve actual source 9px spacer",
    ),
    (
        r'''                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                    ),''',
        r'''                    if (compactContent)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          title.replaceFirst(' ', '\n'),
                          maxLines: 2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                      ),''',
        "Store 2 lines, preserve accepted 100356 FittedBox/title/font for ALL other buttons",
    ),
    (
        r'''              const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 22,
              ),''',
        r'''              if (!compactContent)
                const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 22,
                ),''',
        "Store-only hide chevron; keep it on all original profile tiles",
    ),
)

def apply(src: str) -> str:
    for required in PREREQUISITES:
        if src.count(required) != 1:
            raise ValueError("SAFE_STOP: stage8 prerequisite absent or duplicate: " + required)
    if src.count(STATE) != 1 or src.count(END) != 1:
        raise ValueError("SAFE_STOP: profile state boundaries changed")
    a = src.index(STATE)
    b = src.index(END, a)
    profile = src[a:b]
    if profile.count(GRID) != 1 or profile.count(CARD) != 1 or profile.count(BIO) != 1:
        raise ValueError("SAFE_STOP: original grid/feature-card method anchors changed")
    g = profile.index(GRID)
    c = profile.index(CARD, g)
    e = profile.index(BIO, c)
    grid = profile[g:c]
    method = profile[c:e]
    if MARKER in profile:
        if profile.count(MARKER) != 1 or grid.count(NEW_TILE) != 1 or OLD_TILE in grid:
            raise ValueError("SAFE_STOP: partial or duplicate point8 tile")
        if not all(method.count(new) == 1 for _, new, _ in METHOD_EDITS):
            raise ValueError("SAFE_STOP: point8 compact feature layout changed")
        if any(method.count(old) for old, _, _ in METHOD_EDITS):
            raise ValueError("SAFE_STOP: partial featureCard changes")
        return src
    # Accepted 100356 source is repeatedly dart-formatted while reconstructed.
    # Stage8's original literal came from the old 100263 generator (unformatted),
    # so only ALLOW whitespace-only layout changes; never match another card.
    original_tile = OLD_TILE
    if grid.count(OLD_TILE) != 1:
        candidates = list(re.finditer(
            r'(?ms)^[ \t]*icon:\s*Icons\.photo_library_rounded,.*?'
            r'onTap:\s*\(\)\s*=>\s*_showPhase2Notice\(.*?'
            r'^\s*\),',
            grid,
        ))
        if len(candidates) != 1:
            raise ValueError(
                "SAFE_STOP: original purple Photos card ambiguous after 100356 "
                "formatting; match-count=" + str(len(candidates))
            )
        original_tile = candidates[0].group(0)
        canonical = lambda value: re.sub(r'\s+', '', value)
        if canonical(original_tile) != canonical(OLD_TILE):
            title = grid.count("title: dedaText('الصور', 'Photos')")
            subtitle = grid.count("subtitle: dedaText('قسم مستقل للصور لاحقًا', 'Dedicated photos area later')")
            raise ValueError(
                "SAFE_STOP: original Photos card CONTENT changed, not merely "
                f"formatted (title={title}, subtitle={subtitle}); no replacement"
            )
    if grid.count("        Row(\n") != 3:
        raise ValueError("SAFE_STOP: profile grid row count changed")
    for needle in (
        "title: dedaText('تعديل الملف', 'Edit profile')",
        "title: dedaText('الشارات', 'Badges')",
        "title: dedaText('المفضلة', 'Favorites')",
        "title: dedaText('نشاطاتي', 'My activity')",
        "title: dedaText('عرض الملف العام', 'Public profile')",
    ):
        if grid.count(needle) != 1:
            raise ValueError("SAFE_STOP: other profile grid tile missing: " + needle)
    grid2 = grid.replace(original_tile, NEW_TILE, 1)
    method2 = method
    applied = []
    for old, new, reason in METHOD_EDITS:
        actual = old
        if method2.count(old) != 1:
            # Flutter's formatter may change whitespace (line-wrap, indentation)
            # of the feature-card function. Only accept the EXACT same Dart
            # non-whitespace tokens as the audited approved pre-format snippet.
            compressed = ''.join(c for c in method2 if not c.isspace())
            target = ''.join(c for c in old if not c.isspace())
            count = compressed.count(target)
            if count != 1:
                raise ValueError("SAFE_STOP: original card template diverged: " + reason)
            locations = [i for i, c in enumerate(method2) if not c.isspace()]
            index = compressed.index(target)
            start = locations[index]
            end = locations[index + len(target) - 1] + 1
            actual = method2[start:end]
            if ''.join(c for c in actual if not c.isspace()) != target:
                raise ValueError("SAFE_STOP: card contains semantic differences: " + reason)
        if method2.count(actual) != 1:
            raise ValueError("SAFE_STOP: duplicated original card control: " + reason)
        method2 = method2.replace(actual, new, 1)
        applied.append((actual, new))
    # The historical polish script targets its FIRST 112px occurrence, which
    # may be a different component. The accepted phone source is authoritative:
    # preserve THIS feature card's Ink height byte-for-byte, whether 102 or 112.
    old_height = re.search(r'\bInk\(\s*height:\s*(\d+),', method)
    new_height = re.search(r'\bInk\(\s*height:\s*(\d+),', method2)
    if (old_height is None or new_height is None or
            old_height.group(1) != new_height.group(1) or
            int(old_height.group(1)) not in (102, 112) or
            "Color(0xFF914BE1), Color(0xFF6530B7)" not in grid2):
        raise ValueError("SAFE_STOP: accepted grid size or purple palette changed")
    if method2.count("title.replaceFirst") != 1 or method2.count("FittedBox(") != 2:
        raise ValueError("SAFE_STOP: store label wrapping not enabled")
    # This is a pure source patch. Fully reversing the approved substitutions
    # must reproduce the original profile byte-for-byte.
    reconstructed = method2
    for actual, new in reversed(applied):
        if reconstructed.count(new) != 1:
            raise ValueError("SAFE_STOP: lost exact point8 replacement on rollback")
        reconstructed = reconstructed.replace(new, actual, 1)
    if reconstructed != method or grid2.replace(NEW_TILE, original_tile, 1) != grid:
        raise ValueError("SAFE_STOP: edit leaked to other elements")
    modified_profile = profile[:g] + grid2 + method2 + profile[e:]
    modified_source = src[:a] + modified_profile + src[b:]
    if modified_source[:a] != src[:a] or modified_source[a+len(modified_profile):] != src[b:]:
        raise ValueError("SAFE_STOP: changes outside profile state")
    return modified_source

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: rebuilt lib/main.dart not available")
    original = MAIN.read_text(encoding="utf-8")
    try:
        result = apply(original)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if result != original:
        MAIN.write_text(result, encoding="utf-8")
        print("PASS: repurposed ONLY existing purple Photos tile to Identifier Store, still 112dp")
    else:
        print("PASS: point8 already staged, unchanged")
    print("PASS: opt-in two-line compact title; other cards/wallet, profile IDs and Firebase untouched")
