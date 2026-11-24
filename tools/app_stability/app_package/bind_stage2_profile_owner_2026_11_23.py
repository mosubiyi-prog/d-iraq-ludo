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
    owned = (project / OWNED_IDS).read_text(encoding='utf-8')
    if verify_only:
        verify_owned_row_guard(owned)
    else:
        results[project / OWNED_IDS] = patch_owned_rows(owned)
    return results


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
        if module_path.read_bytes() != expected.read_bytes():
            raise ValueError('PROFILE_GUARD_MODULE_CHANGED')
    else:
        if module_path.exists():
            raise ValueError('PROFILE_GUARD_MODULE_ALREADY_PRESENT')
        new_main = proposed(main, old_store)
        new_main = add_verified_owned_frame_art(new_main)
        # Check all originals before mutating only a disposable build directory.
        main_path.write_text(new_main)
        module_path.write_bytes(expected.read_bytes())
        for path, source in member_changes.items():
            path.write_text(source, encoding='utf-8')
    print('PASS_ASSEMBLED_PROFILE_HADAYA_BADGE_FRAME_LABELS_OWNED_ROWS_NO_SERVICE_MUTATION')
    return 'PASS_PROFILE_SINGLE_ORIGINAL_STORE_PUBLIC_UID_GUARD_NO_PRODUCTION_WRITE'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    print(bind(args.project, args.verify_only))
