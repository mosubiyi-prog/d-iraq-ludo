#!/usr/bin/env python3
"""DEDA «إنت كدها» stage 8 of 16 — repurpose original Photos tile only.

After reconstructed 100356 + approved stages 2..7, swap the EMPTY purple
Photos card with "متجر المعرّفات", keeping its original grid location,
112dp height, purple gradient, neighbor cards, data, and navigation untouched.
Stage9 builds store page; for now tapping opens an honest coming-soon notice.
Compact glyph/title layout applies ONLY to this store tile; all other
_featureCard callers render with the same defaults and dimensions as before.
"""
from pathlib import Path

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
        "    required VoidCallback onTap,\n  }) {",
        "    required VoidCallback onTap,\n    bool compactContent = false,\n  }) {",
        "opt-in compact title, default false for all other cards",
    ),
    (
        "                width: 46,\n                height: 46,",
        "                width: compactContent ? 24 : 46,\n                height: compactContent ? 24 : 46,",
        "make store icon smaller without resizing card",
    ),
    (
        "                child: Icon(icon, color: Colors.white, size: 26),",
        "                child: Icon(icon, color: Colors.white, size: compactContent ? 18 : 26),",
        "scale store icon without changing the other icons",
    ),
    (
        "              const SizedBox(width: 9),",
        "              SizedBox(width: compactContent ? 3 : 9),",
        "store only: narrow icon/text spacer",
    ),
    (
        "                      title,\n                      maxLines: 1,\n                      overflow: TextOverflow.ellipsis,\n                      style: const TextStyle(",
        "                      title,\n                      maxLines: compactContent ? 2 : 1,\n                      overflow: TextOverflow.ellipsis,\n                      style: TextStyle(",
        "display full two-line Arabic shop name",
    ),
    (
        "                        fontSize: 16,\n                      ),\n                    ),\n                    const SizedBox(height: 4),",
        "                        fontSize: compactContent ? 11.5 : 16,\n                      ),\n                    ),\n                    const SizedBox(height: 4),",
        "store-only smaller text, old cards unchanged",
    ),
    (
        "              const Icon(\n                Icons.chevron_left_rounded,\n                color: Colors.white,\n                size: 22,\n              ),",
        "              if (!compactContent)\n                const Icon(\n                  Icons.chevron_left_rounded,\n                  color: Colors.white,\n                  size: 22,\n                ),",
        "store-only remove redundant chevron to make long title legible",
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
    if grid.count(OLD_TILE) != 1:
        raise ValueError("SAFE_STOP: original 100263 purple Photos card not found exactly once")
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
    grid2 = grid.replace(OLD_TILE, NEW_TILE, 1)
    method2 = method
    for old, new, reason in METHOD_EDITS:
        if method2.count(old) != 1:
            raise ValueError("SAFE_STOP: original card template diverged: " + reason)
        method2 = method2.replace(old, new, 1)
    if "height: 112," not in method2 or "Color(0xFF914BE1), Color(0xFF6530B7)" not in grid2:
        raise ValueError("SAFE_STOP: tile size or purple palette unexpectedly lost")
    if method2.count("compactContent ? 2 : 1") != 1:
        raise ValueError("SAFE_STOP: store label wrapping not enabled")
    # This is a pure source patch. Fully reversing the approved substitutions
    # must reproduce the original profile byte-for-byte.
    reconstructed = method2
    for old, new, _ in reversed(METHOD_EDITS):
        reconstructed = reconstructed.replace(new, old, 1)
    if reconstructed != method or grid2.replace(NEW_TILE, OLD_TILE, 1) != grid:
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
