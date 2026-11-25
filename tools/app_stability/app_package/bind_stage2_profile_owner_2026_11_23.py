#!/usr/bin/env python3
"""Bind ONE account-switch guard around the ORIGINAL full DEDA My Store page.

No duplicate profile/store renderer, Firebase writes, admin Auth, new UID,
original source overwrite, Play deployment, checkout or wallet mutation.
Only the disposable fully reconstructed QA app gets this wrapper.
"""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MODULE = 'deda_stage2_profile_owner_my_store_gate_2026_11_23.dart'
IMPORT_ANCHOR = "import 'deda_stage2_google_access_card_2026_11_21.dart';\n"
IMPORT = "import '" + MODULE + "';\n"
STATE = 'class _DedaProfilePhase2PageState'
METHOD = '  Future<void> _openDedaMyStore() async {'
SNAPSHOT = """  Future<void> _openDedaMyStore() async {
    // Stage2 profile: original phone + canonical ID + public UID only.
    // Freeze once BEFORE slow inventory calls; never infer any ownership.
    final _dedaStage2OwnerPhoneAtEntry = DedaPreferences.phone;
    final _dedaStage2AccountEpochAtEntry = DedaPreferences.stabilityAccountEpoch;
    final _dedaStage2OriginalIdAtEntry = _dedaId;
    final _dedaStage2OwnerUidAtEntry = Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid;"""
OLD = ("        builder: (_) => DedaMyStorePage(\n"
       "          originalId: originalId,\n"
       "          items: items,")
NEW = """        builder: (_) => DedaStage2ProfileOwnerBoundMyStore(
          originalId: originalId,
          items: items,
          initialUid: _dedaStage2OwnerUidAtEntry,
          ownerStillCurrent: () =>
              mounted &&
              DedaPreferences.isLoggedIn &&
              DedaPreferences.phone == _dedaStage2OwnerPhoneAtEntry &&
              DedaPreferences.stabilityAccountEpoch == _dedaStage2AccountEpochAtEntry &&
              _dedaId == _dedaStage2OriginalIdAtEntry &&
              originalId == _dedaStage2OriginalIdAtEntry &&
              (Firebase.apps.isEmpty
                  ? _dedaStage2OwnerUidAtEntry == null
                  : FirebaseAuth.instance.currentUser?.uid ==
                      _dedaStage2OwnerUidAtEntry),"""


# The fully assembled original editor is ALREADY protected by the preexisting
# DedaSectionState mixin, DedaSectionOperationContext.wait and account epoch.
# Prove this before reusing it; do NOT create a duplicate editor auth listener.
def audit_original_editor(main: str):
    import re
    matches=list(re.finditer(
        r'(?m)^class\s+_DedaEditProfilePageState\b[^{]*\{', main))
    if len(matches) != 1:
        raise ValueError('PROFILE_AUDIT_STOP:original-editor-class-count:'+str(len(matches)))
    start=matches[0].start()
    next_class=main.find('\nclass ',matches[0].end())
    if next_class < 0:
        raise ValueError('PROFILE_AUDIT_STOP:editor-section-boundary')
    editor=main[start:next_class]
    header=matches[0].group()
    save_start=editor.find('  Future<void> _save() async {')
    if save_start < 0:
        raise ValueError('PROFILE_AUDIT_STOP:original-editor-save-absent')
    save=editor[save_start:]
    required={
        'single-existing-account-epoch-mixin':
            'DedaSectionState<DedaEditProfilePage>' in header,
        'single-original-section-operation':
            'return dedaRunSectionVoid(() async {' in save,
        'owner-current-after-server-receipt':
            'if (!dedaSectionCurrent) return;' in save,
        'account-principal-rechecked-around-awaits':
            'DedaSectionOperationContext.wait(' in save,
        'original-name-writer':
            'DedaPreferences.setUserName(' in save,
        'original-appearance-writer':
            'DedaPreferences.setProfileAppearance(' in save,
        'original-expired-screen':
            'dedaSectionExpiredView()' in editor,
    }
    for name,passed in required.items():
        if not passed:
            raise ValueError('PROFILE_AUDIT_STOP:'+name)


def once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise ValueError(f'PROFILE_SAFE_STOP:{label}:expected1_actual{count}')
    return source.replace(old, new, 1)


def original_profile_span(main: str):
    if main.count(STATE) != 1:
        raise ValueError('PROFILE_SAFE_STOP:profile-class-count')
    first = main.index(STATE)
    tail = main[first:]
    stop = tail.find('\nclass ', len(STATE))
    return first, first + stop if stop >= 0 else len(main)


def proposed(main: str, old_store: str):
    if IMPORT in main or 'DedaStage2ProfileOwnerBoundMyStore(' in main:
        raise ValueError('PROFILE_ALREADY_BOUND_VERIFY_ONLY')
    if old_store.count('class DedaMyStorePage extends StatelessWidget') != 1:
        raise ValueError('PROFILE_SAFE_STOP:original-store-not-unique')
    start, stop = original_profile_span(main)
    section = main[start:stop]
    for label, anchor in [
        ('original-route', OLD),
        ('existing-store-method', METHOD),
        ('original-id', 'final originalId = _dedaId;'),
        ('original-edit', '  Future<void> _openEditProfile() async {'),
    ]:
        if section.count(anchor) != 1:
            raise ValueError(f'PROFILE_SAFE_STOP:missing-profile-{label}:{section.count(anchor)}')
    section = once(section, METHOD, SNAPSHOT, 'capture-original-profile')
    section = once(section, OLD, NEW, 'wrap-existing-store-only')
    main = main[:start] + section + main[stop:]
    main = once(main, IMPORT_ANCHOR, IMPORT_ANCHOR + IMPORT,
                'single-import-following-existing-stage2')
    verify(main, old_store)
    return main


def verify(main: str, old_store: str):
    first, stop = original_profile_span(main)
    section = main[first:stop]
    for label, assertion in [
        ('one-original-profile', main.count(STATE) == 1),
        ('original-unchanged-store-widget',
         old_store.count('class DedaMyStorePage extends StatelessWidget') == 1),
        ('one-wrapper-import', main.count(IMPORT) == 1),
        ('one-wrapped-route', section.count('DedaStage2ProfileOwnerBoundMyStore(') == 1),
        ('old-route-replaced', OLD not in section),
        ('single-owner-freeze', section.count('final _dedaStage2OwnerUidAtEntry =') == 1),
        ('original-phone-check', 'DedaPreferences.phone == _dedaStage2OwnerPhoneAtEntry' in section),
        ('account-epoch-frozen-before-reads', section.count('final _dedaStage2AccountEpochAtEntry = DedaPreferences.stabilityAccountEpoch;') == 1),
        ('account-epoch-check', 'DedaPreferences.stabilityAccountEpoch == _dedaStage2AccountEpochAtEntry' in section),
        ('canonical-id-check', '_dedaId == _dedaStage2OriginalIdAtEntry' in section),
        ('live-uid-check', 'FirebaseAuth.instance.currentUser?.uid ==' in section),
        ('original-store-ui-untouched', "class DedaMyStorePage" in old_store),
    ]:
        if not assertion:
            raise ValueError('PROFILE_VERIFY_FAILED:' + label)



# Add ONLY the missing original asset path to the already RECEIPT-VERIFIED
# paid frame row of the existing original personal My Store. This is not a
# second renderer, item, purchase, or entitlement reader.
PAID_FRAME_ART_MARK = 'DEDA_STAGE2_PROFILE_VERIFIED_PAID_FRAME_ART_ONLY'


def _paid_frame_row(main: str):
    start, stop = original_profile_span(main)
    section = main[start:stop]
    if section.count(METHOD) != 1 or section.count('  Widget _featureGrid() {') != 1:
        raise ValueError('PROFILE_FRAME_ART_STOP:original-store-method')
    mstart = section.index(METHOD)
    mend = section.index('  Widget _featureGrid() {', mstart)
    method = section[mstart:mend]
    if (method.count('DEDA_100377_P12_ALL_PAID_FRAMES_VERIFIED_NOT_ONLY_SELECTED') != 1 or
            method.count('if (DedaOwner18FrameCheckout.live)') != 1 or
            method.count('id: frame.id,') != 1 or
            method.count('DedaOwner18FrameCheckout.verifiedOwnedFrameIds(originalId)') != 1 or
            method.count('ownedFrames.contains(frame.id)') != 1):
        diagnostic = [line.strip() for line in method.splitlines()
                      if any(word in line for word in
                             ('PAID_FRAMES', 'FrameSecureCheckout', 'frame.id',
                              'previewAsset', 'receiptKind', 'frame.nameAr'))]
        raise ValueError('PROFILE_FRAME_ART_STOP:original-receipt-gate-or-item:' +
                         repr(diagnostic[:18]))
    entry = method.index('id: frame.id,')
    row_start = method.rfind('items.add(DedaMyStoreItem(', 0, entry)
    row_end = method.find('));', entry)
    if row_start < 0 or row_end < 0 or row_end > method.find('for (var i = 0;', entry):
        raise ValueError('PROFILE_FRAME_ART_STOP:paid-frame-row-bounds')
    row = method[row_start:row_end + 3]
    for required in (
        'id: frame.id,', 'label: frame.nameAr,',
        'section: DedaMyStoreSection.frames,',
        'proof: DedaMyStoreProof.accountSaved,',
        "receiptKind: 'purchase',", 'active: frameStyle == style,',
    ):
        if required not in row:
            raise ValueError('PROFILE_FRAME_ART_STOP:paid-row-drift:' + required)
    return section, method, row, row_start, row_end


def add_verified_owned_frame_art(main: str) -> str:
    import re
    if PAID_FRAME_ART_MARK in main:
        raise ValueError('PROFILE_FRAME_ART_STOP:duplicate-stage')
    section, method, row, row_start, row_end = _paid_frame_row(main)
    if 'previewAsset:' in row:
        raise ValueError('PROFILE_FRAME_ART_STOP:original-paid-preview-already-exists')
    revised, count = re.subn(
        r'active:\s*frameStyle\s*==\s*style,',
        lambda m: m.group(0) +
                  '\n            // ' + PAID_FRAME_ART_MARK +
                  '\n            previewAsset: frame.assetPath,',
        row,
        count=1,
    )
    if count != 1:
        raise ValueError('PROFILE_FRAME_ART_STOP:active-frame-anchor')
    updated_section = section.replace(row, revised, 1)
    if updated_section == section or updated_section.count(PAID_FRAME_ART_MARK) != 1:
        raise ValueError('PROFILE_FRAME_ART_STOP:single-source-replacement')
    first, end = original_profile_span(main)
    updated = main[:first] + updated_section + main[end:]
    verify_verified_owned_frame_art(updated)
    return updated


def verify_verified_owned_frame_art(main: str):
    section, method, row, start, end = _paid_frame_row(main)
    if (row.count(PAID_FRAME_ART_MARK) != 1 or
            row.count('previewAsset: frame.assetPath,') != 1 or
            main.count(PAID_FRAME_ART_MARK) != 1 or
            method.index('if (DedaOwner18FrameCheckout.live)') >
                method.index('id: frame.id,') or
            method.index('DedaOwner18FrameCheckout.verifiedOwnedFrameIds(originalId)') >
                method.index('id: frame.id,')):
        raise ValueError('PROFILE_FRAME_ART_VERIFY:proven-original-only')


# The reconstructed app starts from the immutable 100380 archive, not raw lib/.
# Reuse the current tested inbox methods without replacing the archived widget:
# the archive contains the unread-gift badge integration and exact artwork.
HADAYA = 'lib/deda_stage74_hadaya_identifier_section.dart'
FREE_INVENTORY = 'lib/deda_100377_profile_free_inventory.dart'
OWNED_IDS = 'lib/deda_stage71_free_owned_use_profile.dart'
HADAYA_MARK = 'DEDA_STAGE2_ASSEMBLED_HADAYA_LIFETIME'
FRAME_NAMES_MARK = 'DEDA_STAGE2_ASSEMBLED_ROYAL_FRAME_LABELS'
OWNED_ROW_MARK = 'DEDA_STAGE2_OWNED_ID_ROW_GENERATION'


def archived_profile_member(path):
    import hashlib
    import json
    import tarfile
    data = REPO / 'tools/app_stability'
    manifest = json.loads((data / '100380-baseline-manifest.json').read_text())
    archive = data / '100380-baseline.tar.gz'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['archiveSHA256']:
        raise ValueError('PROFILE_ARCHIVE_STOP:archive-hash')
    with tarfile.open(archive, 'r:gz') as tar:
        blob = tar.extractfile(path).read()
    if hashlib.sha256(blob).hexdigest() != manifest['files'][path]:
        raise ValueError('PROFILE_ARCHIVE_STOP:member-hash:' + path)
    return blob.decode('utf-8')


def bind_existing_section_lifetime(source):
    # Reproduce the already approved generic guard on a verified source copy.
    # Never run this on the already-bound assembled widget.
    import sys
    root = str(REPO / 'tools/app_stability')
    if root not in sys.path:
        sys.path.insert(0, root)
    from bind_all_sections import bind_file, bind_stateless
    result, _ = bind_file(source)
    result, _ = bind_stateless(result)
    return result


def patch_hadaya_archive(old, tested):
    if HADAYA_MARK in old or '_claimToken' in old or '_onAuthChanged(' in old:
        raise ValueError('PROFILE_HADAYA_STOP:already-bound-or-unexpected')
    for anchor, count in (
        ('DedaStage75UnreadGiftBadge.start(widget.originalId)', 2),
        ('DedaStage75UnreadGiftBadge.markViewed(originalId, gifts)', 1),
        ('DedaStage74IdGiftService.receive(gift)', 1),
        ('DedaStage74IdGiftService.load(originalId)', 1),
    ):
        if old.count(anchor) != count:
            raise ValueError('PROFILE_HADAYA_STOP:original-notification-or-service:' + anchor)
    out = once(old, '  String? _claimingId;\n',
               '  // ' + HADAYA_MARK + '\n'
               '  String? _claimingId;\n  Object? _claimToken;\n'
               '  StreamSubscription<User?>? _auth;\n  String? _observedUid;\n',
               'hadaya-original-fields')
    # Reuse the two tested original-widget methods, not a second service.
    auth_start = tested.index('  void _onAuthChanged(User? user) {')
    auth_end = tested.index('  @override\n  void initState()', auth_start)
    auth_method = tested[auth_start:auth_end]
    if '++_generation;' not in auth_method or '_claimToken = null;' not in auth_method:
        raise ValueError('PROFILE_HADAYA_STOP:tested-auth-method-drift')
    out = once(out, '  @override\n  void initState() {',
               auth_method + '  @override\n  void initState() {',
               'hadaya-auth-method')
    out = once(out, '    super.initState();\n',
               '    super.initState();\n'
               '    _observedUid = _currentUid();\n'
               '    try {\n'
               '      if (Firebase.apps.isNotEmpty) {\n'
               '        _auth = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);\n'
               '      }\n'
               '    } catch (_) { /* Retain the no-Firebase fallback. */ }\n',
               'hadaya-auth-listener')
    out = once(out, '      _claimingId = null;\n      _gifts = null;\n      _error = null;',
               '      _claimingId = null;\n      _claimToken = null;\n'
               '      _gifts = null;\n      _verifiedUid = null;\n      _error = null;',
               'hadaya-original-id-rotation')
    out = once(out, '    _generation++;\n    super.dispose();',
               '    _generation++;\n    _claimToken = null;\n'
               '    _auth?.cancel();\n    super.dispose();',
               'hadaya-dispose')
    out = once(out, '          _gifts = null;\n          _verifiedUid = null;\n          _error = null;',
               '          _gifts = null;\n          _verifiedUid = null;\n'
               '          _claimingId = null;\n          _claimToken = null;\n          _error = null;',
               'hadaya-null-uid')
    out = once(out, '            _claimingId = null;\n',
               '            _claimingId = null;\n            _claimToken = null;\n',
               'hadaya-finally')
    start = out.index('  Future<void> _receive(')
    end = out.index('  Widget _giftTile(', start)
    tested_start = tested.index('  Future<void> _receive(')
    tested_end = tested.index('  Widget _giftTile(', tested_start)
    receive = tested[tested_start:tested_end]
    if ('identical(_claimToken, token)' not in receive or
            'rowGeneration != _generation' not in receive):
        raise ValueError('PROFILE_HADAYA_STOP:tested-receive-method-drift')
    out = out[:start] + receive + out[end:]
    out = once(out, '  Widget _giftTile(DedaStage74IdGift gift) {\n',
               '  Widget _giftTile(DedaStage74IdGift gift) {\n'
               '    final rowGeneration = _generation;\n', 'hadaya-row-generation')
    out = once(out, 'onPressed: _claimingId == null ? () => _receive(gift) : null,',
               'onPressed: !_loading && _claimingId == null\n'
               '                  ? () => _receive(gift, rowGeneration) : null,',
               'hadaya-row-callback')
    for anchor, count in (
        ('DedaStage75UnreadGiftBadge.start(widget.originalId)', 2),
        ('DedaStage75UnreadGiftBadge.markViewed(originalId, gifts)', 1),
        ('DedaStage74IdGiftService.receive(gift)', 1),
        ('DedaStage74IdGiftService.load(originalId)', 1),
        ('class DedaStage74IdGiftsSection extends StatefulWidget', 1),
        ('authStateChanges().listen(_onAuthChanged)', 1),
    ):
        if out.count(anchor) != count:
            raise ValueError('PROFILE_HADAYA_VERIFY:' + anchor)
    return out


def patch_royal_frame_labels(old):
    if ('frameChoices = <int>[0, 3, 4, 5]' not in old or
            FRAME_NAMES_MARK in old):
        raise ValueError('PROFILE_FRAME_NAMES_STOP:original-free-choices')
    return once(old, "      'وردي ملكي',\n      'ذهبي ملكي',\n      'زمردي ملكي',",
                "      // " + FRAME_NAMES_MARK + "\n"
                "      'زمردي ملكي',\n      'ذهبي ملكي',\n      'وردي ملكي',",
                'approved-royal-labels-only')


def _owned_panel_bounds(source):
    state = 'class _DedaStage71OwnedIdsPanelState'
    if source.count(state) != 1:
        raise ValueError('PROFILE_OWNED_IDS_STOP:original-panel-count')
    start = source.index(state)
    end = source.index('\n/// On the user', start)
    return start, end


def verify_owned_row_guard(source):
    start, end = _owned_panel_bounds(source)
    panel = source[start:end]
    for anchor in (
        OWNED_ROW_MARK,
        'rowGeneration != _generation',
        'originalAtBuild != widget.originalId',
        'id != original && !_ids!.any((item) => item.identifier == id)',
        '_use(originalAtBuild, rowGeneration, originalAtBuild)',
        '_use(owned.identifier, rowGeneration, originalAtBuild)',
    ):
        if panel.count(anchor) != 1:
            raise ValueError('PROFILE_OWNED_IDS_VERIFY:' + anchor)


def patch_owned_rows(source):
    start, end = _owned_panel_bounds(source)
    panel = source[start:end]
    if OWNED_ROW_MARK in panel:
        raise ValueError('PROFILE_OWNED_IDS_STOP:duplicate')
    guarded = 'with DedaSectionState<DedaStage71OwnedIdsPanel>' in panel
    # On the real build the general lifetime binder has already wrapped _use.
    # Keep its single operation context, and reject stale rows before entering it.
    if guarded:
        prefix = '  Future<void> _use(String id) async {'
        if ('return dedaRunSectionVoid(() async {' not in panel or
                'DedaSectionOperationContext.wait(' not in panel or
                'if (!dedaSectionCurrent) return dedaSectionExpiredView();' not in panel):
            raise ValueError('PROFILE_OWNED_IDS_STOP:existing-section-guard-missing')
        panel = once(panel, prefix,
            '  // ' + OWNED_ROW_MARK + '\n'
            '  Future<void> _use(String id, int rowGeneration, String originalAtBuild) async {\n'
            '    if (!dedaSectionCurrent || _busy || rowGeneration != _generation ||\n'
            '        originalAtBuild != widget.originalId) return;',
            'owned-row-before-existing-section-entry')
    else:
        panel = once(panel,
            '  Future<void> _use(String id) async {\n    if (_busy) return;',
            '  // ' + OWNED_ROW_MARK + '\n'
            '  Future<void> _use(String id, int rowGeneration, String originalAtBuild) async {\n'
            '    if (!mounted || _busy || rowGeneration != _generation ||\n'
            '        originalAtBuild != widget.originalId) return;',
            'owned-row-entry')
    panel = once(panel, '    if (uid == null || uid != _verifiedUid) return;',
        '    if (uid == null || uid != _verifiedUid || _ids == null ||\n'
        '        (id != original && !_ids!.any((item) => item.identifier == id))) return;',
        'owned-row-current-list')
    panel = once(panel, '    final currentActive = currentRows == null ? null : _active;',
        '    final currentActive = currentRows == null ? null : _active;\n'
        '    final rowGeneration = _generation;\n'
        '    final originalAtBuild = widget.originalId;',
        'owned-row-snapshot')
    panel = once(panel, '() => _use(widget.originalId)',
                 '() => _use(originalAtBuild, rowGeneration, originalAtBuild)',
                 'owned-original-callback')
    panel = once(panel, '() => _use(owned.identifier)',
                 '() => _use(owned.identifier, rowGeneration, originalAtBuild)',
                 'owned-premium-callback')
    patched = source[:start] + panel + source[end:]
    verify_owned_row_guard(patched)
    return patched


def verify_hadaya_section_lifetime(original, expected):
    # Do not allow the new account fence to replace the original shared lane.
    for marker, count in (
        ('with DedaSectionState<DedaStage74IdGiftsSection>', 1),
        ('return dedaRunSectionVoid(() async {', 2),
        ('DedaSectionOperationContext.wait(() => DedaStage74IdGiftService.load(originalId))', 1),
        ('DedaSectionOperationContext.wait(() => DedaStage74IdGiftService.receive(gift))', 1),
        ('DedaSectionOperationContext.wait(() => _refresh())', 1),
        ('if (!dedaSectionCurrent) return dedaSectionExpiredView();', 1),
        ('DedaStage75UnreadGiftBadge.start(widget.originalId)', 2),
        ('DedaStage75UnreadGiftBadge.markViewed(originalId, gifts)', 1),
    ):
        if original.count(marker) != count or expected.count(marker) != count:
            raise ValueError('PROFILE_HADAYA_SHARED_GUARD_STOP:' + marker)
    if ('identical(_claimToken, token)' not in expected or
            'dedaCancelSectionResource(() => _auth?.cancel());' not in expected or
            'rowGeneration != _generation' not in expected):
        raise ValueError('PROFILE_HADAYA_SHARED_GUARD_STOP:new-guard-or-cleanup')


FRAME_PURCHASE_ACTIONS = (
    'lib/deda_owner18_frame_purchase_action.dart',
    'lib/deda_six_frame_purchase_action.dart',
)

def frame_purchase_bounds(source):
    start = '  Future<void> _buy() async {'
    end = '  @override\n  Widget build(BuildContext context) {'
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('FRAME_PURCHASE_SCOPE_DRIFT')
    a, z = source.index(start), source.index(end)
    if z <= a:
        raise ValueError('FRAME_PURCHASE_SCOPE_DRIFT')
    return a, z

def verify_frame_purchase_epoch(source):
    a, z = frame_purchase_bounds(source)
    body = source[a:z]
    for marker, count in (
        ('final purchaseEpoch = _verificationEpoch;', 1),
        ('bool purchaseStillCurrent() =>', 1),
        ('purchaseEpoch == _verificationEpoch && _sameItem(owner, frame, uid)', 1),
        ('purchaseStillCurrent()', 7),
        ('if (purchaseEpoch == _verificationEpoch)', 2),
        ('else if (purchaseEpoch == _verificationEpoch)', 1),
        ('DedaOwner18FrameCheckout.buyOnce(', 1),
        ('DedaOwner18FrameCheckout.isOwned(', 1),
    ):
        if body.count(marker) != count:
            raise ValueError('FRAME_PURCHASE_EPOCH_VERIFY:' + marker)
    if not (body.index('final purchaseEpoch') < body.index('showDialog<bool>') <
            body.index('if (!purchaseStillCurrent())') <
            body.index('DedaOwner18FrameCheckout.buyOnce(')):
        raise ValueError('FRAME_PURCHASE_EPOCH_ORDER')
    if body.count('_sameItem(owner, frame, uid)') != 1:
        raise ValueError('FRAME_PURCHASE_EPOCH_BYPASS')

def patch_frame_purchase_epoch(source):
    a, z = frame_purchase_bounds(source)
    body = source[a:z]
    if 'purchaseEpoch' in body or body.count('_sameItem(owner, frame, uid)') != 6:
        raise ValueError('FRAME_PURCHASE_EPOCH_SOURCE_DRIFT')
    # Keep the existing section guard, checkout and receipt recovery. Reuse
    # the widget's existing epoch for card A -> B -> A while an await is open.
    body = body.replace('_sameItem(owner, frame, uid)', 'purchaseStillCurrent()')
    body = once(body, '    final uid = _currentUid();',
        '    final uid = _currentUid();\n'
        '    final purchaseEpoch = _verificationEpoch;\n'
        '    bool purchaseStillCurrent() =>\n'
        '        purchaseEpoch == _verificationEpoch && _sameItem(owner, frame, uid);',
        'frame-purchase-epoch')
    body = once(body, '    if (!purchaseStillCurrent()) {\n'
        '      _clearIfAccountChanged(owner, frame, uid);',
        '    if (!purchaseStillCurrent()) {\n'
        '      if (purchaseEpoch == _verificationEpoch) {\n'
        '        _clearIfAccountChanged(owner, frame, uid);\n'
        '      }', 'frame-purchase-stale-dialog')
    body = once(body, '      } else {\n        _clearIfAccountChanged(owner, frame, uid);',
        '      } else if (purchaseEpoch == _verificationEpoch) {\n'
        '        _clearIfAccountChanged(owner, frame, uid);', 'frame-purchase-stale-finally')
    result = source[:a] + body + source[z:]
    verify_frame_purchase_epoch(result)
    return result

def profile_member_patches(project, verify_only):
    # Compute every proposed edit before writing any part of the disposable app.
    # Fail closed if an earlier recipe has changed either protected member.
    results = {}
    raw_hadaya = (REPO / HADAYA).read_text(encoding='utf-8')
    for path, transform in (
        (HADAYA, lambda old: patch_hadaya_archive(old, raw_hadaya)),
        (FREE_INVENTORY, patch_royal_frame_labels),
    ):
        original = archived_profile_member(path)
        expected = transform(original)
        if path == HADAYA:
            # 100387 prepare already bound the original inbox via bind_all_sections.
            # Recreate both versions with that SAME deterministic guard generator:
            # the original accepted guard and the new guard on the revised methods.
            original = bind_existing_section_lifetime(original)
            expected = bind_existing_section_lifetime(expected)
            verify_hadaya_section_lifetime(original, expected)
        current = (project / path).read_text(encoding='utf-8')
        if current != (expected if verify_only else original):
            import difflib
            import hashlib
            baseline = expected if verify_only else original
            print('PROFILE_ASSEMBLED_MEMBER_DIFF', path,
                  'expected=' + hashlib.sha256(baseline.encode()).hexdigest(),
                  'actual=' + hashlib.sha256(current.encode()).hexdigest(),
                  flush=True)
            print(''.join(difflib.unified_diff(
                baseline.splitlines(keepends=True), current.splitlines(keepends=True),
                fromfile='expected/' + path, tofile='assembled/' + path, n=3)),
                flush=True)
            raise ValueError('PROFILE_ASSEMBLED_MEMBER_STOP:unexpected-source:' + path)
        results[project / path] = expected
    for path in FRAME_PURCHASE_ACTIONS:
        current = (project / path).read_text(encoding='utf-8')
        if verify_only:
            verify_frame_purchase_epoch(current)
        else:
            results[project / path] = patch_frame_purchase_epoch(current)
    owned = (project / OWNED_IDS).read_text(encoding='utf-8')
    if verify_only:
        verify_owned_row_guard(owned)
    else:
        results[project / OWNED_IDS] = patch_owned_rows(owned)
    return results



PROFILE_CARD_FENCE = 'DEDA_STAGE2_PROFILE_CARD_ACCOUNT_EPOCH'
FRIEND_FRAME_FENCE = 'DEDA_STAGE2_PROFILE_FRIEND_FRAME_ACCOUNT_EPOCH'


def shared_route_parts(main):
    start, stop = original_profile_span(main)
    section = main[start:stop]
    a = section.index('  Widget _featureCard({')
    z = section.index('  Widget _bioCard()', a)
    f = main.index('class _DedaFriendsPageState')
    g = main.index('class _DedaFriendCompactCard', f)
    return start+a, start+z, f, g


def bind_shared_routes(main):
    a, z, _, _ = shared_route_parts(main)
    card = main[a:z]
    if PROFILE_CARD_FENCE in card:
        raise ValueError('PROFILE_SHARED_ROUTE_DUPLICATE')
    card = once(card, '  }) {\n    return Material(',
        '  }) {\n'
        '    // ' + PROFILE_CARD_FENCE + '\n'
        '    final routeEpoch = DedaPreferences.stabilityAccountEpoch;\n'
        '    return Material(', 'profile-card-epoch')
    card = once(card, '        onTap: onTap,',
        '        onTap: () {\n'
        '          if (!dedaSectionCurrent ||\n'
        '              routeEpoch != DedaPreferences.stabilityAccountEpoch) return;\n'
        '          onTap();\n'
        '        },', 'profile-original-card-callback')
    main = main[:a] + card + main[z:]
    _, _, f, g = shared_route_parts(main)
    friends = main[f:g]
    old = '''                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || FirebaseAuth.instance.currentUser?.uid !=
                      session.uid) return;'''
    new = '''                // ''' + FRIEND_FRAME_FENCE + '''
                final countEpoch = DedaPreferences.stabilityAccountEpoch;
                final countGeneration = DedaSocialFriendCount.generation;
                final countLoadGeneration = _friendsGeneration;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!dedaSectionCurrent ||
                      countEpoch != DedaPreferences.stabilityAccountEpoch ||
                      countGeneration != DedaSocialFriendCount.generation ||
                      countLoadGeneration != _friendsGeneration ||
                      !identical(session, _session) ||
                      FirebaseAuth.instance.currentUser?.uid != session.uid) return;'''
    friends = once(friends, old, new, 'profile-friend-count-pending-frame')
    main = main[:f] + friends + main[g:]
    verify_shared_routes(main)
    return main


def verify_shared_routes(main):
    a, z, f, g = shared_route_parts(main)
    card, friends = main[a:z], main[f:g]
    for body, markers in (
        (card, (PROFILE_CARD_FENCE, '!dedaSectionCurrent',
                'routeEpoch != DedaPreferences.stabilityAccountEpoch',
                'onTap();')),
        (friends, (FRIEND_FRAME_FENCE, 'countEpoch != DedaPreferences.stabilityAccountEpoch',
                   'countGeneration != DedaSocialFriendCount.generation',
                   'countLoadGeneration != _friendsGeneration',
                   '!identical(session, _session)',
                   'DedaSocialFriendCount.notifier.value = verifiedCount;')),
    ):
        for marker in markers:
            # Count complete identifiers, not a suffix of accountEpoch.
            # The later friends binder introduces its independent account
            # epoch check; neither check may stand in for the other.
            import re
            if len(re.findall(r'(?<![A-Za-z0-9_$])' + re.escape(marker), body)) != 1:
                raise ValueError('PROFILE_SHARED_ROUTE_VERIFY:' + marker)


def bind(project: Path, verify_only: bool = False):
    project = project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError('PROFILE_PROTECTED_OR_REPO_WRITE_REFUSED')
    main_path = project/'lib/main.dart'
    store_path = project/'lib/deda_100377_my_store_page_staged.dart'
    module_path = project/'lib'/MODULE
    expected = REPO/'lib'/MODULE
    if not all(p.is_file() for p in (main_path, store_path, expected)):
        raise ValueError('PROFILE_REQUIRES_FULL_ORIGINAL_APP_AND_SINGLE_GUARD')
    main, old_store = main_path.read_text(), store_path.read_text()
    if ('DEDA_100377_POINT09_APPEARANCE_ASYNC_ACCOUNT_SCOPE' not in main or
            '_profileAvatarKey(savePhone)' not in main):
        raise ValueError('PROFILE_AUDIT_STOP:existing-appearance-async-guard-missing')
    audit_original_editor(main)
    member_changes = profile_member_patches(project, verify_only)
    if verify_only:
        verify(main, old_store)
        verify_verified_owned_frame_art(main)
        verify_shared_routes(main)
        if module_path.read_bytes() != expected.read_bytes():
            raise ValueError('PROFILE_GUARD_MODULE_CHANGED')
    else:
        if module_path.exists():
            raise ValueError('PROFILE_GUARD_MODULE_ALREADY_PRESENT')
        new_main = proposed(main, old_store)
        new_main = add_verified_owned_frame_art(new_main)
        new_main = bind_shared_routes(new_main)
        # Check all originals before mutating only a disposable build directory.
        main_path.write_text(new_main)
        module_path.write_bytes(expected.read_bytes())
        for path, source in member_changes.items():
            path.write_text(source, encoding='utf-8')
    print('PASS_ASSEMBLED_PROFILE_HADAYA_BADGE_FRAME_LABELS_OWNED_ROWS_NO_SERVICE_MUTATION')
    return 'PASS_PROFILE_SINGLE_ORIGINAL_STORE_PUBLIC_UID_GUARD_NO_PRODUCTION_WRITE'



# Stage 04/01 extends the existing original-profile binder only in disposable
# QA. The default path and the original production-facing source are unchanged.
STAGE04_IMPORT = "import 'deda_stage03_lab_uid_storage_2026_11_25.dart';\n"
STAGE04_MARK = 'DEDA_STAGE04_PROFILE_UID_READ_ONLY'

STAGE04_FIELDS = """ 
  // DEDA_STAGE04_PROFILE_UID_READ_ONLY: original renderer; no old phone I/O.
  static const _stage04LabMode = bool.fromEnvironment('DEDA_STAGE04_PROFILE_LAB')
      || DedaStage03LabStorage.enabled;
  DedaStage04ProfileRead? _stage04Read;
  DedaStage04AppearanceRead? _stage04Appearance;
  DedaAuthSnapshot? _stage04Principal;
  StreamSubscription<User?>? _stage04Auth;
  bool _stage04Expired = false;
  bool _stage04Loading = false;
  ValueNotifier<int>? _stage04Xp, _stage04Points, _stage04Friends;
  DedaStage04ProfileView? get _stage04View {
    if (_stage04Expired) return null;
    try { return _stage04Read?.requireCurrent(); } catch (_) { return null; }
  }
  void _stage04Expire() {
    if (_stage04Expired) return;
    _stage04Expired = true;
    _stage04Read = null;
    _stage04Appearance = null;
    if (mounted) setState(() { _stage04Loading = false; });
  }
  bool _stage04SameSession() {
    try {
      final first = _stage04Principal;
      final current = DedaAuthRuntime.capture();
      return !_stage04Expired && first != null && current != null &&
          first.uid == DedaStage03LabStorage.uid && first.matches(current);
    } catch (_) { return false; }
  }
  void _stage04Start() {
    try {
      _stage04Principal = DedaAuthRuntime.capture();
      if (!_stage04SameSession() || Firebase.apps.isEmpty) {
        _stage04Expired = true;
        return;
      }
      _stage04Auth = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null || user.isAnonymous ||
            user.uid != DedaStage03LabStorage.uid || !_stage04SameSession()) {
          _stage04Expire();
        }
      }, onError: (Object _) => _stage04Expire(), onDone: _stage04Expire);
      unawaited(_stage04Refresh());
    } catch (_) { _stage04Expired = true; }
  }
  Future<void> _stage04Refresh() async {
    if (!mounted || _stage04Loading || !_stage04SameSession()) return;
    setState(() { _stage04Loading = true; _stage04Read = null; _stage04Appearance = null; });
    try {
      final read = await DedaStage03LabStorage.readProfile();
      final view = read.requireCurrent();
      DedaStage04AppearanceRead? appearance;
      try { appearance = await DedaStage03LabStorage.readAppearance(read); }
      catch (_) { /* No local/default fallback or edit on a conflicting journal. */ }
      if (!mounted || !_stage04SameSession()) return;
      read.requireCurrent();
      setState(() {
        (_stage04Xp ??= ValueNotifier<int>(view.xp)).value = view.xp;
        (_stage04Points ??= ValueNotifier<int>(view.taskPoints)).value = view.taskPoints;
        (_stage04Friends ??= ValueNotifier<int>(view.acceptedFriends)).value = view.acceptedFriends;
        _stage04Read = read;
        _stage04Appearance = appearance;
        _stage04Loading = false;
      });
    } catch (_) {
      if (mounted && _stage04SameSession()) {
        setState(() { _stage04Read = null; _stage04Loading = false; });
      }
    }
  }
  Widget _stage04HeldProfile() => Scaffold(
    backgroundColor: _cream,
    appBar: AppBar(title: Text(dedaText('ملفي', 'My profile')),
        backgroundColor: _navy, foregroundColor: Colors.white),
    body: Center(child: _stage04Loading
      ? const CircularProgressIndicator()
      : Text(dedaText('الملف محجوب حتى التحقق من الحساب الموحد.',
          'Profile held until the unified account is verified.'),
          key: const Key('deda_stage04_profile_held'),
          textAlign: TextAlign.center)),
  );
  void _stage04CopyId() {
    final view = _stage04View;
    if (!_stage04SameSession() || view == null) return;
    unawaited(Clipboard.setData(ClipboardData(text: view.activeId)));
  }
  Future<void> _stage04OpenEditor() async {
    final opening = _stage04Appearance;
    if (opening == null || !_stage04SameSession()) {
      _showPhase2Notice('تعذر التحقق من سجل المظهر الموحد.',
          'The unified appearance record could not be verified.');
      return;
    }
    final changed = await Navigator.push<bool>(context, MaterialPageRoute<bool>(
      builder: (_) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, auth) {
          try {
            if (auth.hasError || auth.connectionState == ConnectionState.waiting ||
                auth.data?.uid != DedaStage03LabStorage.uid ||
                !_stage04SameSession()) return _stage04HeldProfile();
            opening.requireCurrent();
            return DedaEditProfilePage(stage04Appearance: opening);
          } catch (_) { return _stage04HeldProfile(); }
        })));
    if ((changed == true || DedaStage03LabStorage.nameCandidateEnabled) &&
        mounted && _stage04SameSession()) {
      await _stage04Refresh();
    }
  }
  void _stage04OpenCard(String title) {
    final read = _stage04Read;
    final view = _stage04View;
    if (read == null || view == null || !_stage04SameSession()) return;
    Widget child;
    if (title == dedaText('تعديل الملف', 'Edit profile')) {
      unawaited(_stage04OpenEditor());
      return;
    } else if (title == dedaText('الشارات', 'Badges')) {
      child = DedaSixAchievementsPage(
          level: DedaSocialProgressWallet.levelForXp(
              view.xp.clamp(0, 1 << 30).toInt()),
          isArabic: DedaLanguageState.isArabic);
    } else if (title == dedaText('المفضلة', 'Favorites') ||
        title == dedaText('نشاطاتي', 'My activity')) {
      child = SavedPlacesPage(
          showFavorites: title == dedaText('المفضلة', 'Favorites'),
          stage04ProfileRead: read);
    } else if (title == dedaText('متجري', 'My Store')) {
      try {
        final items = <DedaMyStoreItem>[
          DedaMyStoreItem(id: view.originalId, label: view.originalId,
              section: DedaMyStoreSection.identifiers,
              proof: DedaMyStoreProof.accountSaved,
              active: view.activeId == view.originalId),
        ];
        final selected = _stage04Appearance?.selection;
        final chosenStyle = selected?.frameStyle(
            (i) => DedaLabPremiumFrameStyles.byProfileStyle(i)?.id);
        items.addAll(DedaProfileFreeInventory.forDevice(
            avatarStyle: selected?.avatar ?? -1, frameStyle: chosenStyle ?? -1,
            backgroundStyle: selected?.background ?? -1).where(
              (item) => item.proof == DedaMyStoreProof.basicFree));
        final owned = view.verifiedPaidFrameIds;
        final rendered = <String>{};
        for (var style = 6; style <= 18; style++) {
          final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
          if (frame == null || !owned.contains(frame.id)) continue;
          if (!rendered.add(frame.id)) throw StateError('duplicate-frame-catalog');
          items.add(DedaMyStoreItem(id: frame.id, label: frame.nameAr,
              section: DedaMyStoreSection.frames,
              proof: DedaMyStoreProof.serverVerified,
              receiptKind: 'purchase', previewAsset: frame.assetPath,
              active: selected?.frame == frame.id));
        }
        if (rendered.length != owned.length) throw StateError('frame-catalog-incomplete');
        for (final id in view.acceptedGiftIds) {
          items.add(DedaMyStoreItem(id: id, label: id,
              section: DedaMyStoreSection.identifiers,
              proof: DedaMyStoreProof.serverVerified,
              receiptKind: 'gift', active: id == view.activeId));
        }
        child = DedaMyStorePage(originalId: view.originalId, items: items,
            isArabic: DedaLanguageState.isArabic, stage04ProfileRead: read,
            onOpenEditProfile: _stage04Appearance == null ? null : () {
              if (!_stage04SameSession() || _stage04View == null) return;
              Navigator.pop(context);
              unawaited(_stage04OpenEditor());
            });
      } catch (_) {
        _showPhase2Notice('تعذر التحقق من المقتنيات الموحدة.',
            'Unified inventory could not be verified.');
        return;
      }
    } else if (title == dedaText('عرض الملف العام', 'Public profile preview')) {
      child = DedaPublicProfilePreviewPage(stage04ProfileRead: read,
          stage04Appearance: _stage04Appearance?.selection);
    } else {
      // Do not open a legacy phone editor or acquisition shop while
      // its complete authoritative inputs are unavailable.
      _showPhase2Notice('هذه الوظيفة بانتظار مصدر موحد مؤمّن.',
          'This function is held until its unified source is secured.');
      return;
    }
    Navigator.push<void>(context, MaterialPageRoute<void>(
      builder: (_) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, auth) {
          try {
            if (auth.hasError || auth.connectionState == ConnectionState.waiting ||
                auth.data?.uid != DedaStage03LabStorage.uid ||
                !_stage04SameSession()) return _stage04HeldProfile();
            read.requireCurrent();
            return child;
          } catch (_) { return _stage04HeldProfile(); }
        })));
  }
"""

def _stage04_region(source, marker, next_marker, transform):
    if source.count(marker) != 1:
        raise ValueError('STAGE04_PROFILE_STOP:region:' + marker)
    start = source.index(marker)
    end = source.find(next_marker, start + len(marker))
    if end < 0:
        raise ValueError('STAGE04_PROFILE_STOP:region-end:' + marker)
    return source[:start] + transform(source[start:end]) + source[end:]

def _stage04_hero(body):
    import re
    # Retain the original hero gradient, typography and level/badge widgets.
    # The incomplete lab record has no selected appearance. Never show a
    # device's saved avatar/frame/background as if it belonged to this UID.
    for name, field in [('name','displayName'), ('id','originalId')]:
        pattern = r'final ' + name + r'\s*=\s*([^;]+);'
        matches = list(re.finditer(pattern, body))
        if len(matches) != 1:
            raise ValueError('STAGE04_PROFILE_STOP:hero-' + name)
        match = matches[0]
        body = body[:match.start()] + (
            'final ' + name + ' = _stage04LabMode ? _stage04View!.' +
            field + ' : (' + match.group(1) + ');') + body[match.end():]
    if body.count('DedaPreferences.profileBackgroundStyle') < 2:
        raise ValueError('STAGE04_PROFILE_STOP:hero-background')
    body = body.replace('DedaPreferences.profileBackgroundStyle',
        '(_stage04LabMode ? (_stage04Appearance?.selection?.background ?? 0) : DedaPreferences.profileBackgroundStyle)')
    avatar = 'child: ValueListenableBuilder<int>('
    body = once(body, avatar, """child: _stage04LabMode
                          ? (_stage04Appearance?.selection != null
                              ? DedaFramedAvatar(
                                  avatarStyle: _stage04Appearance!.selection!.avatar,
                                  frameStyle: _stage04Appearance!.selection!.frameStyle(
                                    (i) => DedaLabPremiumFrameStyles.byProfileStyle(i)?.id),
                                  size: avatarSize)
                              : SizedBox(width: avatarSize, height: avatarSize,
                              child: Center(child: Icon(Icons.person_outline,
                                size: avatarSize * 0.45, color: Colors.white,
                                semanticLabel: dedaText('المظهر غير متاح',
                                    'Appearance unavailable')))))
                          : ValueListenableBuilder<int>(""", 'stage04-hero-avatar')
    body = once(body, '                    DedaStage48ActiveInkProfileSlot(',
        """                    if (_stage04LabMode)
                      GestureDetector(
                        onTap: _stage04CopyId,
                        child: Text(_stage04View!.activeId,
                            key: const Key('deda_stage04_verified_id'),
                            style: const TextStyle(color: Color(0xFFFFD76A),
                                fontWeight: FontWeight.w900, fontSize: 18)),
                      )
                    else
                    DedaStage48ActiveInkProfileSlot(""", 'stage04-hero-id')
    if body.count('DedaSocialProgressWallet.xpNotifier') < 2:
        raise ValueError('STAGE04_PROFILE_STOP:hero-xp')
    return body.replace('DedaSocialProgressWallet.xpNotifier',
        '(_stage04LabMode ? _stage04Xp! : DedaSocialProgressWallet.xpNotifier)')

def _stage04_level(body):
    return once(body, 'valueListenable: DedaSocialProgressWallet.xpNotifier,',
        'valueListenable: _stage04LabMode ? _stage04Xp! : DedaSocialProgressWallet.xpNotifier,',
        'stage04-level-xp')

def _stage04_stats(body):
    body = once(body, 'child: ValueListenableBuilder<int>(\n            valueListenable: DedaDiamondsWallet.balanceNotifier,',
        """child: _stage04LabMode
              ? _statCard(icon: Icons.diamond_rounded, value: '—',
                  label: dedaText('الماسات', 'Diamonds'),
                  color: const Color(0xFF7639D4), surface: const Color(0xFFF1E8FF))
              : ValueListenableBuilder<int>(
            valueListenable: DedaDiamondsWallet.balanceNotifier,""", 'stage04-full-wallet-held')
    body = once(body, 'valueListenable: DedaSocialFriendCount.notifier,',
        'valueListenable: _stage04LabMode ? _stage04Friends! : DedaSocialFriendCount.notifier,',
        'stage04-friends')
    body = once(body, 'valueListenable: DedaTaskEngine.totalPointsNotifier,',
        'valueListenable: _stage04LabMode ? _stage04Points! : DedaTaskEngine.totalPointsNotifier,',
        'stage04-task-points')
    return once(body, 'onTap: () => setState(', 'onTap: _stage04LabMode ? null : () => setState(',
        'stage04-no-local-point-reward')

def _stage04_build(body):
    body = once(body, 'if (!dedaSectionCurrent) return dedaSectionExpiredView();',
        'if (!dedaSectionCurrent) return dedaSectionExpiredView();\n'
        '    if (_stage04LabMode && _stage04View == null) return _stage04HeldProfile();',
        'stage04-before-render')
    body = once(body, 'onPressed: _openEditProfile,',
        'onPressed: _stage04LabMode ? _stage04OpenEditor : _openEditProfile,', 'stage04-edit-held')
    return once(body, '          ValueListenableBuilder<int>(\n            valueListenable: DedaTaskEngine.totalPointsNotifier,',
        '          if (!_stage04LabMode)\n          ValueListenableBuilder<int>(\n            valueListenable: DedaTaskEngine.totalPointsNotifier,',
        'stage04-local-reward-panel-held')

def _stage04_profile(source):
    a,z = original_profile_span(source)
    profile = source[a:z]
    if STAGE04_MARK in profile or STAGE04_IMPORT in source:
        raise ValueError('STAGE04_PROFILE_ALREADY_BOUND')
    brace = profile.index('{')
    profile = profile[:brace+1] + STAGE04_FIELDS + profile[brace+1:]
    profile = once(profile, '    super.initState();', """    super.initState();
    if (_stage04LabMode) {
      WidgetsBinding.instance.addObserver(this);
      _stage04Start();
      return;
    }""", 'stage04-no-legacy-init')
    profile = once(profile, 'void didChangeAppLifecycleState(AppLifecycleState state) {',
        """void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stage04LabMode) {
      if (state == AppLifecycleState.resumed) unawaited(_stage04Refresh());
      return;
    }""", 'stage04-no-legacy-resume')
    profile = once(profile, 'void dispose() {', """void dispose() {
    if (_stage04LabMode) {
      _stage04Expired = true;
      unawaited(_stage04Auth?.cancel());
      _stage04Xp?.dispose();
      _stage04Points?.dispose();
      _stage04Friends?.dispose();
    }""", 'stage04-dispose')
    # New helper uses an expression-bodied widget, so the existing build anchor
    # still selects the one original build method.
    profile = _stage04_region(profile, 'Widget build(BuildContext context) {',
        '  Widget _profileBackdrop()', _stage04_build)
    profile = _stage04_region(profile, '  Widget _profileHeroCard() {',
        '  Widget _avatar(', _stage04_hero)
    profile = _stage04_region(profile, '  Widget _profileLevelProgressCard() {',
        '  Widget _statsRow() {', _stage04_level)
    profile = _stage04_region(profile, '  Widget _statsRow() {',
        '  Widget _statCard(', _stage04_stats)
    profile = _stage04_region(profile, '  Widget _featureCard(', '  Widget _bioCard() {',
        lambda body: once(body, '          onTap();',
          '          if (_stage04LabMode) { _stage04OpenCard(title); return; }\n          onTap();',
          'stage04-original-card-routing'))
    sync_import = "import 'deda_private_data_sync.dart';\n"
    imports = STAGE04_IMPORT
    if sync_import not in source:
        imports += sync_import
    return imports + source[:a] + profile + source[z:]

STAGE04_PLACES_FIELDS = """
  bool _stage04PlacesError = false;
  Future<void> _stage04LoadPlaces() async {
    final read = widget.stage04ProfileRead!;
    try {
      final raw = await DedaStage03LabStorage.readProfilePlaceRecords(read,
          favorites: widget.showFavorites);
      final items = <PlaceInfo>[];
      for (final row in raw) {
        final decoded = jsonDecode(row);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('profile-place-record');
        }
        items.add(PlaceInfo.fromJson(decoded));
      }
      read.requireCurrent();
      if (!dedaSectionCurrent) return;
      setState(() { _places = items; _loading = false; _stage04PlacesError = false; });
    } catch (_) {
      if (!dedaSectionCurrent) return;
      setState(() { _loading = false; _stage04PlacesError = true; });
    }
  }
"""

def _stage04_places_widget(body):
    body = once(body, '  final bool showFavorites;',
        '  final bool showFavorites;\n  final DedaStage04ProfileRead? stage04ProfileRead;',
        'stage04-places-input')
    return once(body, '    required this.showFavorites,',
        '    required this.showFavorites,\n    this.stage04ProfileRead,', 'stage04-places-ctor')

def _stage04_places_state(body):
    brace = body.index('{')
    body = body[:brace+1] + STAGE04_PLACES_FIELDS + body[brace+1:]
    body = once(body, 'Future<void> _load() async {',
        'Future<void> _load() async {\n'
        '    if (widget.stage04ProfileRead != null) return _stage04LoadPlaces();',
        'stage04-places-read')
    body = once(body, 'Future<void> _removeFavorite(PlaceInfo place) async {',
        'Future<void> _removeFavorite(PlaceInfo place) async {\n'
        '    if (widget.stage04ProfileRead != null) return;',
        'stage04-places-no-legacy-write')
    body = once(body, 'onTap: () async {',
        'onTap: () async {\n'
        '                          if (widget.stage04ProfileRead != null) return;',
        'stage04-places-no-legacy-details')
    body = once(body, 'onPressed: () => _removeFavorite(place),',
        'onPressed: widget.stage04ProfileRead == null ? () => _removeFavorite(place) : null,',
        'stage04-places-no-remove')
    return once(body, 'if (!dedaSectionCurrent) return dedaSectionExpiredView();',
        """if (!dedaSectionCurrent) return dedaSectionExpiredView();
    if (widget.stage04ProfileRead != null) {
      try { widget.stage04ProfileRead!.requireCurrent(); }
      catch (_) { return dedaSectionExpiredView(); }
      if (_stage04PlacesError) {
        return Scaffold(appBar: AppBar(title: Text(dedaText('الأماكن المحفوظة', 'Saved places'))),
          body: Center(child: Text(dedaText('تعذر التحقق من سجل الأماكن الموحد.',
            'The unified places record could not be verified.'), textAlign: TextAlign.center)));
      }
    }""", 'stage04-places-no-empty-fallback')


def _stage04_store(body):
    body = once(body, "import 'deda_qa32_active_account_scope.dart';",
        "import 'deda_qa32_active_account_scope.dart';\n" + STAGE04_IMPORT,
        'stage04-store-import')
    body = once(body, '    this.onOpenEditProfile,',
        '    this.onOpenEditProfile,\n    this.stage04ProfileRead,', 'stage04-store-ctor')
    body = once(body, '  final String originalId;',
        '  final String originalId;\n  final DedaStage04ProfileRead? stage04ProfileRead;',
        'stage04-store-read')
    body = once(body, 'Widget build(BuildContext context) {', """Widget build(BuildContext context) {
    DedaStage04ProfileView? unified;
    if (stage04ProfileRead != null) {
      try {
        unified = stage04ProfileRead!.requireCurrent();
        if (unified.originalId != originalId) throw StateError('profile-store-uid');
      } catch (_) {
        return Scaffold(body: Center(child: Text(_t('تعذر التحقق من الحساب', 'Account verification failed'))));
      }
    }""", 'stage04-store-build')
    body = once(body, 'DedaQa32ActiveAccountScope(', """if (unified != null)
              Column(children: <Widget>[
                Text(unified.activeId, key: const Key('deda_stage04_store_active_id')),
                if (unified.activeId != originalId) Text(originalId),
                Text(_t('المقتنيات المثبتة فقط؛ المظهر والممتلكات الأخرى غير متاحة بعد.',
                    'Verified inventory only; appearance and other items are not yet available.'),
                    textAlign: TextAlign.center),
              ])
            else
            DedaQa32ActiveAccountScope(""", 'stage04-store-no-legacy-id')
    body = once(body,
        "'لا توجد مقتنيات مثبتة للعرض هنا حاليًا.',",
        "unified != null ? 'لا تتوفر بيانات مثبتة لهذا القسم بعد.' : 'لا توجد مقتنيات مثبتة للعرض هنا حاليًا.',",
        'stage04-store-no-false-empty-ar')
    return once(body, "'No confirmed items to show here yet.',",
        "unified != null ? 'Verified data for this section is not yet available.' : 'No confirmed items to show here yet.',",
        'stage04-store-no-false-empty-en')


def _stage04_public_preview(body):
    import re
    body = once(body, 'const DedaPublicProfilePreviewPage({super.key});',
        'const DedaPublicProfilePreviewPage({super.key, this.stage04ProfileRead, this.stage04Appearance});\n'
        '  final DedaStage04Appearance? stage04Appearance;\n'
        '  final DedaStage04ProfileRead? stage04ProfileRead;', 'stage04-preview-ctor')
    # Keep the original preview layout. The lab branch never reads a phone
    # identity or shows a local appearance as the unified account's appearance.
    for name, field in [('name','displayName'), ('id','activeId')]:
        pattern = r'final ' + name + r'\s*=\s*([^;]+);'
        match = list(re.finditer(pattern, body))
        if len(match) != 1: raise ValueError('STAGE04_PREVIEW_STOP:' + name)
        m=match[0]
        body=body[:m.start()] + ('final ' + name + ' = stage04ProfileRead != null ? '
            'stage04ProfileRead!.requireCurrent().' + field + ' : (' + m.group(1) + ');') + body[m.end():]
    body = once(body, 'DedaPreferences.profileBackgroundStyle,',
        'stage04ProfileRead != null ? (stage04Appearance?.background ?? 0) : DedaPreferences.profileBackgroundStyle,',
        'stage04-preview-background')
    body = once(body, 'ValueListenableBuilder<int>(',
        """if (stage04ProfileRead != null && stage04Appearance != null)
                  DedaFramedAvatar(avatarStyle: stage04Appearance!.avatar,
                      frameStyle: stage04Appearance!.frameStyle(
                          (i) => DedaLabPremiumFrameStyles.byProfileStyle(i)?.id),
                      size: 124)
                else if (stage04ProfileRead != null)
                  SizedBox(height: 124, width: 124, child: Center(child: Icon(
                    Icons.person_outline, size: 56,
                    semanticLabel: dedaText('المظهر غير متاح', 'Appearance unavailable'))))
                else
                ValueListenableBuilder<int>(""", 'stage04-preview-avatar')
    body = once(body, 'child: DedaSixActiveIdentity(',
        """child: stage04ProfileRead != null
                      ? Text(id, textAlign: TextAlign.center,
                          key: const Key('deda_stage04_public_preview_id'))
                      : DedaSixActiveIdentity(""", 'stage04-preview-id')
    return body


def _stage04_editor_widget(body):
    return once(body, 'const DedaEditProfilePage({super.key});',
        'const DedaEditProfilePage({super.key, this.stage04Appearance});\n'
        '  final DedaStage04AppearanceRead? stage04Appearance;', 'stage04-editor-ctor')


def _stage04_editor_state(body):
    body = once(body, '    super.initState();', """    super.initState();
    final opening = widget.stage04Appearance;
    if (opening != null) {
      var verifiedName = '';
      try {
        final view = opening.requireCurrent();
        final chosen = opening.selection;
        // Initial preview only when no prior selection exists.
        _avatarStyle = chosen?.avatar ?? 0;
        _frameStyle = chosen?.frameStyle(
            (i) => DedaLabPremiumFrameStyles.byProfileStyle(i)?.id) ?? 3;
        _backgroundStyle = chosen?.background ?? 0;
        final owned = view.verifiedPaidFrameIds;
        for (var style=6; style<=18; style++) {
          if (owned.contains(DedaLabPremiumFrameStyles.byProfileStyle(style)?.id)) {
            _serverVerifiedPaidStyles.add(style);
          }
        }
        if (_serverVerifiedPaidStyles.contains(_frameStyle)) {
          _confirmedActiveFrame = _frameStyle;
        }
        verifiedName = view.displayName;
      } catch (_) {
        // Initialize the original late fields but never render them as
        // account data or write when verification fails.
        _stage04EditorHeld = true;
        _avatarStyle = 0; _frameStyle = 3; _backgroundStyle = 0;
        _serverVerifiedPaidStyles.clear();
        _confirmedActiveFrame = null;
      }
      _name = TextEditingController(text: verifiedName);
      return;
    }""", 'stage04-editor-no-phone-init')
    body = once(body, '  bool _saving = false;', """  bool _saving = false;
  bool _stage04EditorHeld = false;
  bool _stage04ReopenRequired = false;
  Future<void> _stage04SaveAppearance() async {
    final opening = widget.stage04Appearance!;
    if (_saving || _stage04EditorHeld || _stage04ReopenRequired) return;
    setState(() { _saving = true; _error = null; });
    try {
      opening.requireCurrent();
      final selection = DedaStage04Appearance.fromStyles(
          avatar: _avatarStyle, frameStyle: _frameStyle,
          background: _backgroundStyle,
          paidIdAt: (i) => DedaLabPremiumFrameStyles.byProfileStyle(i)?.id);
      if (DedaStage03LabStorage.nameCandidateEnabled) {
        final outcome = await DedaStage03LabStorage.saveProfileCandidate(
            opening, _name.text, selection);
        opening.requireCurrent();
        if (!mounted) return;
        if (outcome.complete) {
          Navigator.pop(context, true);
          return;
        }
        // Never retry from an old opening revision. Closing the editor
        // refreshes the parent even if a write acknowledgement was lost.
        String status(DedaStage04SavePart part) {
          switch (part) {
            case DedaStage04SavePart.unchanged:
              return dedaText('دون تغيير', 'Unchanged');
            case DedaStage04SavePart.confirmed:
              return dedaText('مؤكد', 'Confirmed');
            case DedaStage04SavePart.unconfirmed:
              return dedaText('غير مؤكد', 'Unconfirmed');
            case DedaStage04SavePart.notAttempted:
              return dedaText('لم تتم المحاولة', 'Not attempted');
          }
        }
        setState(() {
          _stage04ReopenRequired = true;
          _error = dedaText('الاسم: ', 'Name: ') + status(outcome.name) +
              dedaText('، المظهر: ', ', Appearance: ') + status(outcome.appearance) +
              dedaText('. أغلق المحرر وافتحه مجدداً للتحقق من الحفظ.',
                  '. Close and reopen the editor to verify the save.');
        });
        return;
      }
      final result = await DedaStage03LabStorage.saveAppearance(opening, selection);
      opening.requireCurrent();
      if (!mounted) return;
      if (result.status == DedaPrivateDataStatus.saved) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = dedaText(
            'لم يتأكد الحفظ؛ أعد المحاولة بنفس الاختيار أو أغلق الشاشة عند التعارض.',
            'Save not confirmed; retry the same selection or close on conflict.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = dedaText('تعذر تأكيد حفظ المظهر.',
          'Appearance save could not be confirmed.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }""", 'stage04-editor-save')
    body = once(body, '  Future<void> _save() async {',
        '  Future<void> _save() async {\n'
        '    if (widget.stage04Appearance != null) return _stage04SaveAppearance();',
        'stage04-editor-bypass-legacy-save')
    body = once(body, 'if (!dedaSectionCurrent) return dedaSectionExpiredView();',
        """if (!dedaSectionCurrent) return dedaSectionExpiredView();
    if (widget.stage04Appearance != null) {
      try {
        widget.stage04Appearance!.requireCurrent();
        if (_stage04EditorHeld) return dedaSectionExpiredView();
      } catch (_) { return dedaSectionExpiredView(); }
    }""", 'stage04-editor-current')
    body = once(body, 'const DedaUnifiedCurrencyStrip(),',
        'if (widget.stage04Appearance == null) const DedaUnifiedCurrencyStrip(),',
        'stage04-editor-no-local-wallet')
    body = once(body, 'child: DedaSixActiveIdentity(',
        """child: widget.stage04Appearance != null
                              ? SelectableText(widget.stage04Appearance!.requireCurrent().activeId)
                              : DedaSixActiveIdentity(""", 'stage04-editor-id')
    body = once(body, 'if (index >= 6)\n                                  DedaSixFramePurchaseAction(',
        """if (index >= 6 && widget.stage04Appearance != null)
                                  TextButton(
                                    onPressed: _saving || !_serverVerifiedPaidStyles.contains(index)
                                        ? null : () => setState(() {
                                            _frameStyle = index; _previewFrameStyle = null;
                                          }),
                                    child: Text(_serverVerifiedPaidStyles.contains(index)
                                        ? dedaText('استخدام', 'Use')
                                        : dedaText('الشراء محجوب', 'Purchase held')))
                                else if (index >= 6)
                                  DedaSixFramePurchaseAction(""", 'stage04-editor-no-checkout')
    body = once(body, 'controller: _name,',
        'controller: _name,\n                    readOnly: widget.stage04Appearance != null && (!DedaStage03LabStorage.nameCandidateEnabled || _saving || _stage04ReopenRequired),',
        'stage04-editor-name-authority-held')
    return body

def bind_stage04_lab(project: Path):
    project = project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError('STAGE04_PROFILE_DISPOSABLE_REQUIRED')
    main_path = project/'lib/main.dart'
    original = main_path.read_text()
    # The previously approved profile binder and source-parity audit must run first.
    verify(original, (project/'lib/deda_100377_my_store_page_staged.dart').read_text())
    verify_verified_owned_frame_art(original)
    verify_shared_routes(original)
    modified = _stage04_profile(original)
    modified = _stage04_region(modified, 'class DedaEditProfilePage extends StatefulWidget',
        '\nclass ', _stage04_editor_widget)
    modified = _stage04_region(modified, 'class _DedaEditProfilePageState',
        '\nclass ', _stage04_editor_state)
    store_path = project/'lib/deda_100377_my_store_page_staged.dart'
    store_modified = _stage04_store(store_path.read_text())
    modified = _stage04_region(modified, 'class DedaPublicProfilePreviewPage extends StatelessWidget',
        '\nclass ', _stage04_public_preview)
    modified = _stage04_region(modified, 'class SavedPlacesPage extends StatefulWidget',
        '\nclass ', _stage04_places_widget)
    modified = _stage04_region(modified, 'class _SavedPlacesPageState',
        '\nclass ', _stage04_places_state)
    for name in ('deda_stage03_lab_uid_storage_2026_11_25.dart',
                 'deda_stage02_lab_single_uid_2026_11_25.dart',
                 'deda_private_data_sync.dart',
                 'deda_step2_local_places_settings_evidence.dart'):
        target = project/'lib'/name
        source = REPO/'lib'/name
        if target.exists() and target.read_bytes() != source.read_bytes():
            raise ValueError('STAGE04_PROFILE_STOP:dependency-drift:' + name)
    for name in ('deda_stage03_lab_uid_storage_2026_11_25.dart',
                 'deda_stage02_lab_single_uid_2026_11_25.dart',
                 'deda_private_data_sync.dart',
                 'deda_step2_local_places_settings_evidence.dart'):
        target = project/'lib'/name
        if not target.exists(): target.write_bytes((REPO/'lib'/name).read_bytes())
    main_path.write_text(modified)
    store_path.write_text(store_modified)
    test = project/'test/deda_stage04_original_profile_hold_test.dart'
    if test.exists():
        raise ValueError('STAGE04_PROFILE_TEST_ALREADY_EXISTS')
    test.write_text("""import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart' as app;
void main() {
  testWidgets('original profile remains held without an approved lab principal',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: app.DedaProfilePhase2Page()));
    await tester.pump();
    expect(find.byKey(const Key('deda_stage04_profile_held')), findsOneWidget);
    expect(find.byKey(const Key('deda_stage04_verified_id')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
""")
    print('PASS_STAGE04_ORIGINAL_PROFILE_SOURCE_BINDING_NO_LEGACY_INIT_OR_PLACE_WRITE')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--stage04-lab', action='store_true')
    args = parser.parse_args()
    if args.stage04_lab:
        if args.verify_only: raise ValueError('stage04-lab and verify-only are exclusive')
        bind_stage04_lab(args.project)
    else:
        print(bind(args.project, args.verify_only))
