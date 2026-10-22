#!/usr/bin/env python3
"""Point11: attach the six-tier *locked* achievements screen to the actual
reconstructed DEDA profile "الشارات" tile, not to an orphan preview screen.

No XP, wallet, owner proof, cloud account, grants, prices or existing cosmetic
"شارات وإطارات" store is touched. Level release remains OFF until verified.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARK = "// DEDA_100377_POINT11_REAL_PROFILE_ACHIEVEMENTS_NAV_SAFE_OFF"
IMPORT = "import 'deda_100377_level_achievements_page_staged.dart';\n"
IMPORT_ANCHOR = "import 'deda_100377_profile_free_inventory.dart';\n"
START = "  Widget _featureGrid() {"
STOP = "  Widget _featureCard("
OLD_ACTION = """onTap: () => _showPhase2Notice(
                  'تم تجهيز مكان الشارات. سيتم ربطها بالإنجازات في مرحلتها.',
                  'The badges area is ready and will be linked to achievements in its dedicated phase.',
                ),"""
NEW_ACTION = """// DEDA_100377_POINT11_REAL_PROFILE_ACHIEVEMENTS_NAV_SAFE_OFF
                // Preview only: no authenticated, server-verified level
                // is available here; never infer one from local task XP.
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DedaLevelAchievementsPage(
                        verifiedServerLevel: null,
                        hasVerifiedAccountAndLevel: false,
                      ),
                    ),
                  );
                },"""

def patch(src: str) -> str:
    if MARK in src:
        if (src.count(MARK) != 1 or src.count(IMPORT) != 1 or
                src.count("title: dedaText('الشارات', 'Badges')") != 1 or
                OLD_ACTION in src):
            raise ValueError("SAFE_STOP_POINT11_PARTIAL_NAV_PATCH")
        return src
    if (src.count(IMPORT_ANCHOR) != 1 or src.count(START) != 1 or
            src.count(STOP) != 1 or src.count(OLD_ACTION) != 1):
        raise ValueError("SAFE_STOP_POINT11_PROFILE_OR_IMPORT_DRIFT")
    begin = src.index(START)
    end = src.index(STOP, begin)
    grid = src[begin:end]
    if (grid.count(OLD_ACTION) != 1 or
            grid.count("title: dedaText('الشارات', 'Badges')") != 1 or
            grid.count("title: dedaText('متجري', 'My Store')") != 1 or
            grid.count("title: dedaText('متجر المعرّفات', 'Identifier store')") != 1):
        raise ValueError("SAFE_STOP_POINT11_BADGE_TILE_OR_SHOPS_MISMATCH")
    grid = grid.replace(OLD_ACTION, NEW_ACTION, 1)
    src = src[:begin] + grid + src[end:]
    src = src.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + IMPORT, 1)
    if src.count(MARK) != 1 or src.count(IMPORT) != 1:
        raise ValueError("SAFE_STOP_POINT11_NAV_PATCH_CORRUPT")
    return src

if __name__ == "__main__":
    original = MAIN.read_text(encoding="utf-8")
    patched = patch(original)
    if patched == original:
        raise SystemExit("SAFE_STOP_POINT11_ALREADY_PATCHED")
    MAIN.write_text(patched, encoding="utf-8")
    print("PASS_POINT11_TRUE_PROFILE_BADGES_TILE_OPENS_SIX_LEVEL_PREVIEW")
    print("SAFE_LEVEL_AND_UNLOCK_UNVERIFIED_RELEASE_OFF_NO_CLOUD_WRITE")
