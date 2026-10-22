#!/usr/bin/env python3
"""Point01: attach trusted LAB frame ownership to real reconstructed 100377.

Runs AFTER stage_deda_100375_all_16_lab_original_royal_frames_native.py.
13 premium frames can be previewed without touching saved appearance.
The buy control stays fail-CLOSED until real server rules are approved.
No local deductions, no automatic grant, no Firebase/Play deployment.
"""
from pathlib import Path
import re

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT01_LAB_FRAME_CHECKOUT_GUARDED'
IMPORT = "import 'deda_lab_frame_purchase_action.dart';\n"
A = 'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {'
PREF = 'class DedaPreferences {'

def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1 or IMPORT not in src:
            raise ValueError('SAFE_STOP_PARTIAL_POINT01')
        return src
    a = src.index(A)
    b = src.find('\nclass ', a+len(A))
    if b < 0:
        raise ValueError('SAFE_STOP_EDIT_SECTION_BOUNDARY')
    e = src[a:b]
    anchors = (
        'children: List<Widget>.generate(16, (offset)',
        'final index = offset + 3;',
        'final free = dedaProfileFrameIsFree(index);',
        'final selected = free && _frameStyle == index;',
        'onTap: free\n                          ? () => setState(() => _frameStyle = index)\n                          : _lockedFrameMessage,',
        'DedaProfileFramePreview(\n                            style: index,',
        'frameStyle: _frameStyle,',
        'Future<void> _save() async {',
    )
    for x in anchors:
        if x not in e:
            raise ValueError('SAFE_STOP_POINT01_RENDER_DRIFT ' + x[:70])
    # Parent state only, no changes to other application areas.
    e = e.replace(
        'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {',
        'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {\n'
        '  '+MARK+'\n'
        '  int? _labPreviewStyle;\n'
        '  final Set<int> _serverVerifiedPaidStyles = <int>{};\n',
        1)
    e = e.replace(
        'final selected = free && _frameStyle == index;',
        'final selected = (_labPreviewStyle ?? _frameStyle) == index;', 1)
    e = e.replace(
        'onTap: free\n                          ? () => setState(() => _frameStyle = index)\n                          : _lockedFrameMessage,',
        '''onTap: free
                          ? () => setState(() { _frameStyle = index; _labPreviewStyle = null; })
                          : () => setState(() => _labPreviewStyle = index),''', 1)
    # Only the sticky portrait renderer, never saved preferences.
    p = e.index('child: DedaFramedAvatar(')
    q = e.index('frameStyle: _frameStyle,', p)
    e = e[:q] + 'frameStyle: _labPreviewStyle ?? _frameStyle,' + e[q+len('frameStyle: _frameStyle,'):]
    # Price + authenticated ownership action live BELOW each locked frame.
    thumb = '''DedaProfileFramePreview(
                            style: index,
                            avatarStyle: _avatarStyle,
                            size: cell,
                            selected: selected,
                          ),'''
    if e.count(thumb) != 1:
        raise ValueError('SAFE_STOP_POINT01_THUMB_DRIFT')
    e = e.replace(thumb, thumb+'''
                          if (index >= 6)
                            DedaLabFramePurchaseAction(
                              key: ValueKey<String>('deda_frame_checkout_$index'),
                              originalId: DedaBackend.personalShareIdForPhone(
                                DedaPreferences.phone,
                              ).trim(),
                              frameId: DedaLabPremiumFrameStyles.byProfileStyle(index)!.id,
                              onVerifiedOwned: () => setState(() {
                                _serverVerifiedPaidStyles.add(index);
                                _frameStyle = index;
                                _labPreviewStyle = null;
                              }),
                            ),''', 1)
    # Never accidentally persist a paid preview when saving a name/background.
    saveAnchor = 'Future<void> _save() async {'
    e = e.replace(saveAnchor, saveAnchor+'''
    if (_frameStyle >= 6 && !_serverVerifiedPaidStyles.contains(_frameStyle)) {
      setState(() => _error = 'الملكية المدفوعة غير مؤكدة من الخادم؛ لم نحفظ الإطار.');
      return;
    }
''', 1)
    src = src[:a] + e + src[b:]
    if IMPORT in src or src.count("import 'package:flutter/material.dart';\n") != 1:
        raise ValueError('SAFE_STOP_POINT01_IMPORT_DRIFT')
    src = src.replace("import 'package:flutter/material.dart';\n",
                      "import 'package:flutter/material.dart';\n"+IMPORT,1)
    # Preserve historical cached ownership; only widen frame slot integer.
    pa = src.index(PREF)
    pb = src.index('\nenum DedaTaskEvent', pa)
    prefs = src[pa:pb]
    n = 0
    def widen(m):
        nonlocal n
        val = m.group(0)
        if '.clamp(0, 5)' in val:
            n += 1
            return val.replace('.clamp(0, 5)', '.clamp(0, 18)')
        return val
    prefs = re.sub(r'profileFrameStyle\s*=\s*[^;]{0,230};', widen, prefs, flags=re.S)
    if n < 3:
        raise ValueError('SAFE_STOP_POINT01_LOCAL_FRAME_STORAGE_DRIFT ' + str(n))
    src = src[:pa] + prefs + src[pb:]
    if src.count(MARK) != 1 or src.count(IMPORT) != 1:
        raise ValueError('SAFE_STOP_POINT01_FINAL')
    return src

if __name__ == '__main__':
    source = MAIN.read_text()
    result = patch(source)
    if source == result:
        raise ValueError('SAFE_STOP_POINT01_ALREADY_PRESENT')
    MAIN.write_text(result)
    print('PASS_POINT01_13_PRICED_AT_1000_SECURE_PURCHASE_UI_STAGED')
    print('PASS_POINT01_PREVIEW_NEVER_SAVED_OR_DEBITED')
    print('PASS_POINT01_PAID_EQUIP_REQUIRES_SERVER_RECEIPT')
    print('NO_LIVE_CHECKOUT_NO_FIRESTORE_DEPLOY_NO_PLAY_PUBLISH')
