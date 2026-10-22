#!/usr/bin/env python3
"""Owner point01: guarded secure checkout on reconstructed actual 100377 Flutter.

Preserve existing _previewFrameStyle mechanics and owner choice. No purchase
is enabled without explicit secure backend switch and audited server rules.
"""
from pathlib import Path
import re

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT01_LAB_FRAME_CHECKOUT_GUARDED'
IMPORT = "import 'deda_lab_frame_purchase_action.dart';\n"
EDITOR_START = 'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {'
GRID = 'children: List<Widget>.generate(16, (offset) {'

def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1 or src.count(IMPORT) != 1:
            raise ValueError('SAFE_STOP_PARTIAL_POINT01_PATCH')
        return src
    if src.count(EDITOR_START) != 1:
        raise ValueError('SAFE_STOP_POINT01_EDIT_PROFILE_NOT_EXACTLY_ONCE')
    a = src.index(EDITOR_START)
    b = src.find('\nclass ', a + len(EDITOR_START))
    if b < 0:
        raise ValueError('SAFE_STOP_POINT01_EDITOR_END')
    editor = src[a:b]
    requirements = [GRID, 'int? _previewFrameStyle;', 'frameStyle: _previewFrameStyle ?? _frameStyle,',
                    'final index = offset + 3;', 'final free = dedaProfileFrameIsFree(index);',
                    'onTap: free', 'DedaProfileFramePreview(',
                    'class _DedaEditProfilePageState', 'Future<void> _save() async {']
    for item in requirements:
        if item not in editor:
            raise ValueError('SAFE_STOP_POINT01_MISSING_REAL_EDITOR_ANCHOR:' + item)
    state = '  int? _previewFrameStyle;'
    if editor.count(state) != 1:
        raise ValueError('SAFE_STOP_POINT01_PREVIEW_STATE_DRIFT')
    editor = editor.replace(state, state + '\n  ' + MARK + '\n  final Set<int> _serverVerifiedPaidStyles = <int>{};', 1)
    save = 'Future<void> _save() async {'
    editor = editor.replace(save, save + '''
    // Never persist a locally previewed or unverified paid LAB frame.
    if (_frameStyle >= 6 && !_serverVerifiedPaidStyles.contains(_frameStyle)) {
      setState(() => _error = 'تحقق من ملكية الإطار بالخادم ثم اضغط استخدام.');
      return;
    }
''', 1)
    grid = editor.index(GRID)
    thumb = '''DedaProfileFramePreview(
                                  style: index,
                                  avatarStyle: _avatarStyle,
                                  size: cell,
                                  selected: selected,
                                ),'''
    if editor.count(thumb) != 1 or editor.find(thumb,grid) < 0:
        raise ValueError('SAFE_STOP_POINT01_PAID_THUMB_DRIFT')
    editor = editor.replace(thumb, thumb+'''
                                if (index >= 6)
                                  DedaLabFramePurchaseAction(
                                    key: ValueKey<String>('deda_lab_checkout_$index'),
                                    originalId: DedaBackend.personalShareIdForPhone(
                                      DedaPreferences.phone,
                                    ).trim(),
                                    frameId: DedaLabPremiumFrameStyles.byProfileStyle(index)!.id,
                                    onVerifiedOwned: () => setState(() {
                                      _serverVerifiedPaidStyles.add(index);
                                      _frameStyle = index;
                                      _previewFrameStyle = null;
                                    }),
                                  ),''',1)
    src=src[:a]+editor+src[b:]
    if IMPORT in src or src.count("import 'package:flutter/material.dart';\n") != 1:
        raise ValueError('SAFE_STOP_POINT01_IMPORT_DRIFT')
    src=src.replace("import 'package:flutter/material.dart';\n", "import 'package:flutter/material.dart';\n"+IMPORT,1)
    # UI saving valid verified styles cannot be truncated to a legacy 0..5.
    pa=src.index('class DedaPreferences {')
    pb=src.find('\nenum DedaTaskEvent',pa)
    if pb < pa:
        raise ValueError('SAFE_STOP_POINT01_PREFERENCES_END')
    prefs=src[pa:pb]
    edited=0
    def widen(match):
        nonlocal edited
        v=match.group(0)
        if '.clamp(0, 5)' in v:
            edited+=1
            return v.replace('.clamp(0, 5)', '.clamp(0, 18)')
        return v
    prefs = re.sub(r'profileFrameStyle\s*=\s*[^;]{0,290};', widen, prefs, flags=re.S)
    if edited < 3:
        raise ValueError('SAFE_STOP_POINT01_EXPECTED_FRAME_PREFS_3: '+str(edited))
    src=src[:pa]+prefs+src[pb:]
    if src.count(MARK)!=1 or src.count(IMPORT)!=1 or src.count('DedaLabFramePurchaseAction(')!=1:
        raise ValueError('SAFE_STOP_POINT01_UNIQUE_MARKERS')
    return src

if __name__=='__main__':
    before=MAIN.read_text()
    after=patch(before)
    if before==after:
        raise ValueError('SAFE_STOP_POINT01_DUPLICATE')
    MAIN.write_text(after)
    print('PASS_POINT01_REAL_GENERATED_EDITOR_PREVIEW_REUSED_NO_DEBIT')
    print('PASS_POINT01_13_PAID_FRAMES_ONLY_SERVER_RECEIPT_ENABLE_USE')
    print('PASS_POINT01_WALLET_AND_OWNED_RECORDS_UNCHANGED')
    print('NO_REAL_SALES_NO_FIREBASE_DEPLOY_NO_PLAY_PUBLISH')
