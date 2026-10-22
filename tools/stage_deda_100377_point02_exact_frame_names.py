#!/usr/bin/env python3
"""Point02: display the actual verified LAB frame name on every 1000-diamond tile.

This runs ONLY after the stage 100375 native 16-frame grid and stage 100377
secure frame checkout are installed on the reconstructed real Flutter source.
Never change wallet, transaction, ownership, name catalog or selected frame.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT02_EXACT_LAB_PAID_FRAME_NAMES'
EDITOR = 'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {'
GRID = 'children: List<Widget>.generate(16, (offset) {'


def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1:
            raise ValueError('SAFE_STOP_POINT02_PARTIALLY_APPLIED')
        return src
    if src.count(EDITOR) != 1 or src.count(GRID) != 1:
        raise ValueError('SAFE_STOP_POINT02_NATIVE_16_FRAME_EDITOR_NOT_READY')
    if src.count('DEDA_100377_POINT01_LAB_FRAME_CHECKOUT_GUARDED') != 1:
        raise ValueError('SAFE_STOP_POINT02_POINT01_NOT_INSTALLED')
    a = src.index(EDITOR)
    b = src.find('\nclass ', a + len(EDITOR))
    if b < 0:
        raise ValueError('SAFE_STOP_POINT02_EDITOR_BOUNDARY')
    edit = src[a:b]
    grid = edit.index(GRID)
    label_start = edit.find('child: Text(', grid)
    if label_start < grid:
        raise ValueError('SAFE_STOP_POINT02_NO_REAL_FRAME_LABEL')
    max_lines = edit.find('maxLines: 1,', label_start)
    if max_lines < label_start:
        raise ValueError('SAFE_STOP_POINT02_REAL_LABEL_LAYOUT_DRIFT')
    old = edit[label_start:max_lines + len('maxLines: 1,')]
    for token in ("free", "index == 3", "index == 4", "'زمردي ملكي'", "'ذهبي ملكي'", "'وردي ملكي'"):
        if token not in old:
            raise ValueError('SAFE_STOP_POINT02_PAID_LABEL_DRIFT:' + token)
    if old.count('وردي ملكي') != 1 or old.count('child: Text(') != 1:
        raise ValueError('SAFE_STOP_POINT02_LABEL_NOT_UNIQUE')
    # Free royal styles 3/4/5 retain their approved original names. The 13
    # paid styles 6..18 read their true original title from the same immutable
    # catalog as the frame art and price, instead of defaulting to "وردي ملكي".
    new = """// DEDA_100377_POINT02_EXACT_LAB_PAID_FRAME_NAMES
                                  child: Text(
                                    index >= 6
                                        ? DedaLabPremiumFrameStyles.byProfileStyle(index)!.nameAr
                                        : (index == 3
                                            ? dedaText('زمردي ملكي', 'Royal emerald')
                                            : index == 4
                                                ? dedaText('ذهبي ملكي', 'Royal gold')
                                                : dedaText('وردي ملكي', 'Royal rose')),
                                    maxLines: 3,"""
    edit = edit.replace(old, new, 1)
    after = src[:a] + edit + src[b:]
    if after.count(MARK) != 1 or after.count('DedaLabPremiumFrameStyles.byProfileStyle(index)!.nameAr') != 1:
        raise ValueError('SAFE_STOP_POINT02_MARKER_OR_CATALOG_MISMATCH')
    return after


if __name__ == '__main__':
    before = MAIN.read_text(encoding='utf-8')
    after = patch(before)
    if before == after:
        raise SystemExit('SAFE_STOP_POINT02_ALREADY_PATCHED')
    MAIN.write_text(after, encoding='utf-8')
    print('PASS_POINT02_13_PAID_FRAMES_SHOW_EXACT_VERIFIED_ORIGINAL_NAMES')
    print('PASS_POINT02_THREE_FREE_ROYAL_NAMES_AND_REAL_PAID_ASSETS_RETAINED')
    print('PASS_POINT02_NO_WALLET_NO_OWNERSHIP_NO_PREVIEW_ACTION_MUTATION')
