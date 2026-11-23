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
              _dedaId == _dedaStage2OriginalIdAtEntry &&
              originalId == _dedaStage2OriginalIdAtEntry &&
              (Firebase.apps.isEmpty
                  ? _dedaStage2OwnerUidAtEntry == null
                  : FirebaseAuth.instance.currentUser?.uid ==
                      _dedaStage2OwnerUidAtEntry),"""


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
        ('canonical-id-check', '_dedaId == _dedaStage2OriginalIdAtEntry' in section),
        ('live-uid-check', 'FirebaseAuth.instance.currentUser?.uid ==' in section),
        ('original-store-ui-untouched', "class DedaMyStorePage" in old_store),
    ]:
        if not assertion:
            raise ValueError('PROFILE_VERIFY_FAILED:' + label)


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
    if verify_only:
        verify(main, old_store)
        if module_path.read_bytes() != expected.read_bytes():
            raise ValueError('PROFILE_GUARD_MODULE_CHANGED')
    else:
        if module_path.exists():
            raise ValueError('PROFILE_GUARD_MODULE_ALREADY_PRESENT')
        new_main = proposed(main, old_store)
        # Check all originals before mutating only a disposable build directory.
        main_path.write_text(new_main)
        module_path.write_bytes(expected.read_bytes())
    return 'PASS_PROFILE_SINGLE_ORIGINAL_STORE_PUBLIC_UID_GUARD_NO_PRODUCTION_WRITE'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    print(bind(args.project, args.verify_only))
