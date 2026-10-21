#!/usr/bin/env python3
"""Stage native DEDA original 3 royal image frames as free & selectable.

Only AFTER reconstructing phone-verified main.dart and royalty WebP assets.
Does not touch the 13 staged paid artworks, accounts, Firebase, payments,
premium identifier cards or private signed app identity.
"""
from pathlib import Path
MAIN = Path('lib/main.dart')
MARK = '// DEDA_LAB_3_EXISTING_ROYAL_FRAMES_FREE_SAVE_RELOAD_SAFE'
FREE='bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 3;'
FREE_NEW='bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 6;'
# Exact historical persistence expression for the current 6 bundled slots.
PREF_LOAD1='(prefs.getInt(_profileFrameKey(phone)) ?? 0).clamp(0, 2).toInt();'
PREF_LOAD2='''profileFrameStyle = (prefs.getInt(_profileFrameKey(normalizedPhone)) ?? 0)
        .clamp(0, 2)
        .toInt();'''
PREF_SAVE='profileFrameStyle = frameStyle.clamp(0, 2).toInt();'


def patch_source(src: str) -> str:
    if MARK in src:
        for required in (FREE_NEW, 'profileFrameStyle = frameStyle.clamp(0, 5).toInt();'):
            if required not in src: raise ValueError('SAFE_STOP_3_ROYAL_PARTIAL_PATCH')
        return src
    required=(FREE, PREF_LOAD1, PREF_LOAD2, PREF_SAVE,
              'class DedaFramedAvatar extends StatelessWidget {',
              'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {',
              'final free = dedaProfileFrameIsFree(index);',
              'List<Widget>.generate(6, (index) {',
              'frameStyle: _frameStyle,',
              'assets/deda_royal_frames/royal_frame_')
    for anchor in required:
        if src.count(anchor) != 1 and anchor not in (
                'List<Widget>.generate(6, (index) {',
                'frameStyle: _frameStyle,',
                'assets/deda_royal_frames/royal_frame_'):
            raise ValueError('SAFE_STOP_3_ROYAL_ANCHOR ' + anchor + ' count ' + str(src.count(anchor)))
        if anchor not in src:
            raise ValueError('SAFE_STOP_3_ROYAL_ANCHOR_MISSING ' + anchor)
    # This ensures the three original royal frames (indices 3,4,5) are
    # actual usable/savable selections, not a misleading unlocked display.
    src=src.replace(FREE, MARK+'\n'+FREE_NEW,1)
    src=src.replace(PREF_LOAD1,
                    '(prefs.getInt(_profileFrameKey(phone)) ?? 0).clamp(0, 5).toInt();',1)
    src=src.replace(PREF_LOAD2,
          '''profileFrameStyle = (prefs.getInt(_profileFrameKey(normalizedPhone)) ?? 0)
        .clamp(0, 5)
        .toInt();''',1)
    src=src.replace(PREF_SAVE,
                    'profileFrameStyle = frameStyle.clamp(0, 5).toInt();',1)
    if src.count(MARK)!=1 or FREE in src or PREF_LOAD1 in src or PREF_LOAD2 in src or PREF_SAVE in src:
        raise ValueError('SAFE_STOP_3_ROYAL_POST_VERIFY')
    return src


if __name__ == '__main__':
    before=MAIN.read_text()
    after=patch_source(before)
    if after==before:
        raise SystemExit('SAFE_STOP_3_ROYAL_NOT_APPLIED')
    MAIN.write_text(after)
    print('PASS: frame slots 0..5 all FREE, including existing 3 royal WebPs at 3..5.')
    print('PASS: selecting an original royal slot 3..5 persists instead of clamping to 2.')
    print('PASS: no diamond debit or Firebase/account migration; 13 new LAB frames not yet native bundled.')
