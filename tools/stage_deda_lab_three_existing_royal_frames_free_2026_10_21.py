#!/usr/bin/env python3
"""Make 3 existing royal WEBP frames free in live profile and savable (no wallet).

Apply on REAL reconstructed DEDA source. Historical reconstruction stages may
already have upgraded SharedPreferences clamps 0..2 -> 0..5; detect both
versions and never change unrelated preference fields or balances.
"""
from pathlib import Path
import re

MAIN=Path('lib/main.dart')
MARK='// DEDA_LAB_3_EXISTING_ROYAL_FRAMES_FREE_SAVE_RELOAD_SAFE'
OLD_FREE='bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 3;'
NEW_FREE='bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 6;'

def patch_source(src: str) -> str:
    if MARK in src:
        if src.count(MARK)!=1 or src.count(NEW_FREE)!=1:
            raise ValueError('SAFE_STOP_PARTIAL_ROYAL_FREE_PATCH')
        return src
    if src.count(OLD_FREE)!=1 or src.count('class DedaPreferences {')!=1:
        raise ValueError('SAFE_STOP_ROYAL_FREE_OR_PREFERENCES_BASE_DRIFT')
    for s in ('class DedaFramedAvatar extends StatelessWidget {',
              'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {',
              'final free = dedaProfileFrameIsFree(index);',
              'assets/deda_royal_frames/royal_frame_',
              'frameStyle: _frameStyle,'):
        if s not in src:
            raise ValueError('SAFE_STOP_REAL_ROYAL_APPEARANCE_MISSING '+s)
    a=src.index('class DedaPreferences {')
    b=src.find('\nenum DedaTaskEvent',a)
    if b<a:
        raise ValueError('SAFE_STOP_PREFERENCES_SECTION_BOUNDARY')
    prefs=src[a:b]
    # Scan ONLY profileFrameStyle assignments; no other aspect of preferences
    # (balance, account ID, points, place ownership) may be modified.
    expressions=list(re.finditer(r'profileFrameStyle\s*=\s*[^;]{0,250};',
                                 prefs,flags=re.S))
    if len(expressions)<4:
        raise ValueError('SAFE_STOP_PROFILE_FRAME_LOAD_AND_SAVE_MISSING')
    changed=0
    sections=[]
    prev=0
    for m in expressions:
        expr=m.group(0)
        newexpr=expr
        if '.clamp(0, 2)' in expr:
            newexpr=expr.replace('.clamp(0, 2)', '.clamp(0, 5)')
            changed+=1
        elif '.clamp(0, 5)' in expr or expr.strip().endswith('= 0;') or              '.getInt(' in expr or expr.endswith('= frameStyle;'):
            pass
        else:
            # Unrecognized assignment: preserve it, but never mistake it for
            # a safe proof that the new royal slots can persist.
            pass
        sections.append(prefs[prev:m.start()]+newexpr)
        prev=m.end()
    sections.append(prefs[prev:])
    newprefs=''.join(sections)
    # The write must support frame slots through index 5.
    if 'profileFrameStyle = frameStyle.clamp(0, 5).toInt();' not in newprefs:
        raise ValueError('SAFE_STOP_ROYAL_5_FRAME_SAVE_CLAMP_NOT_CONFIRMED')
    if 'profileFrameStyle = frameStyle.clamp(0, 2)' in newprefs:
        raise ValueError('SAFE_STOP_ROYAL_OLD_CLAMP_LEFT')
    src=src[:a]+newprefs+src[b:]
    src=src.replace(OLD_FREE,MARK+'\n'+NEW_FREE,1)
    if src.count(MARK)!=1 or src.count(NEW_FREE)!=1:
        raise ValueError('SAFE_STOP_ROYAL_FINAL_COUNT')
    return src

if __name__=='__main__':
    before=MAIN.read_text()
    after=patch_source(before)
    if after==before:
        raise SystemExit('SAFE_STOP_ROYAL_ALREADY_APPLIED')
    MAIN.write_text(after)
    print('PASS_ROYAL_3_ORIGINAL_IMAGES_FREE_AND_SAVABLE_NO_WALLET')
    print('PASS_ROYAL_3_LEGACY_FREE_STILL_AVAILABLE_NO_GEMS_CHANGED')
    print('PASS_ROYAL_13_PAID_LAB_ASSETS_REMINDER_UNBUNDLED_YET')
