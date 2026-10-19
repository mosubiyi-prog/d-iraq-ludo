#!/usr/bin/env python3
"""Render owner-exclusive ID administration with original four DEDA artworks.

Applied only after the exact 100359 Flutter main.dart has been reconstructed,
because checked-in raw lib/main.dart is not the generated signed app. Reuses
DedaPremiumIdCard, so the shop/admin/profile cannot diverge into simple
color-border mockups again. No live grant, wallet or production mutation.
"""
from pathlib import Path

ADMIN = Path("lib/deda_exclusive_ids_admin_page.dart")
GENERATED_MAIN = Path("lib/main.dart")
ANCHOR = "  Widget _preview(DedaExclusiveAdminId item, String color) {"
END = "  Widget _exclusiveItem(DedaExclusiveAdminId item) {"
IMPORT = "import 'main.dart' show DedaPremiumIdCard, DedaPremiumIdCardColor;\n"
STAMP = "// DEDA_100360_ADMIN_USES_ORIGINAL_FOUR_FULL_FOILS"
REPLACEMENT = """  // DEDA_100360_ADMIN_USES_ORIGINAL_FOUR_FULL_FOILS
  DedaPremiumIdCardColor _originalArtwork(String color) {
    switch (color) {
      case 'gold':
        return DedaPremiumIdCardColor.gold;
      case 'diamond':
        return DedaPremiumIdCardColor.diamond;
      case 'royal':
        return DedaPremiumIdCardColor.royal;
      case 'pink':
        return DedaPremiumIdCardColor.pink;
      default:
        throw StateError('invalid-server-fixed-premium-color');
    }
  }

  Widget _preview(DedaExclusiveAdminId item, String color) {
    return DedaPremiumIdCard(
      key: ValueKey<String>('deda_stage19_one_preview_' + item.identifier),
      identifier: item.identifier,
      color: _originalArtwork(color),
      height: 50,
    );
  }

"""

def apply(admin_src: str, main_src: str) -> str:
    for required in (
        "class DedaPremiumIdCard extends",
        "enum DedaPremiumIdCardColor",
        "DedaPremiumIdCard({",
    ):
        if required not in main_src:
            raise ValueError("SAFE_STOP: original full premium artwork absent: " + required)
    if STAMP in admin_src:
        if admin_src.count(STAMP) != 1 or IMPORT not in admin_src or REPLACEMENT not in admin_src:
            raise ValueError("SAFE_STOP: admin original-artwork stage corrupted")
        return admin_src
    if admin_src.count(ANCHOR) != 1 or admin_src.count(END) != 1:
        raise ValueError("SAFE_STOP: manager preview exact boundaries differ")
    a = admin_src.index(ANCHOR)
    b = admin_src.index(END, a)
    old = admin_src[a:b]
    for required in (
        "Container(", "_cardColor(color)", "height: 50",
        "'deda_stage19_one_preview_' + item.identifier",
    ):
        if required not in old:
            raise ValueError("SAFE_STOP: old manager-only color border changed")
    new = admin_src[:a] + REPLACEMENT + admin_src[b:]
    if "import 'package:flutter/material.dart';\n" not in new or IMPORT in new:
        raise ValueError("SAFE_STOP: invalid manager import")
    new = new.replace("import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\n" + IMPORT, 1)
    # Forensic: removing the one import and reverting the one replacement
    # recovers the exact original manager UI without changing admin role logic.
    if new.replace(IMPORT, "", 1).replace(REPLACEMENT, old, 1) != admin_src:
        raise ValueError("SAFE_STOP: unrelated management code would change")
    return new

if __name__ == "__main__":
    old = ADMIN.read_text(encoding="utf-8")
    main = GENERATED_MAIN.read_text(encoding="utf-8")
    updated = apply(old, main)
    if updated != old:
        ADMIN.write_text(updated, encoding="utf-8")
    print("PASS: GM uses identical 50px four full premium artworks, not plain border")
    print("PASS: original private catalog, grants, recipients, history and wallet untouched")
