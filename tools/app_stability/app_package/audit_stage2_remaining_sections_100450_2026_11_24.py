"""Read-only comparison against the independently reconstructed signed 100450.
No Firebase, APK, runtime changes, or feature activation. Fail on unexplained drift.
"""
import argparse
import difflib
import importlib.util
from pathlib import Path

import bind_stage2_bottom_navigation_2026_11_24 as bottom
import bind_stage2_profile_owner_2026_11_23 as profile

ROOT = Path(__file__).resolve().parents[3]
home = bottom.home


def member(source, marker):
    a, z = home.span(source, marker)
    return source[a:z]


def equal(name, expected, actual):
    if expected != actual:
        diff = difflib.unified_diff(expected.splitlines(), actual.splitlines(),
            fromfile='100450-plus-approved-binders/' + name,
            tofile='current/' + name, n=3, lineterm='')
        print('\n'.join(list(diff)[:160]), flush=True)
        raise ValueError('REMAINING_100450_UNEXPLAINED_DRIFT:' + name)
    print('REMAINING_100450_PARITY_PASS', name, flush=True)


def read(project, name):
    return (project/'lib'/name).read_text(encoding='utf-8')


def gifts(reference, project):
    old, new = read(reference, 'main.dart'), read(project, 'main.dart')
    for name in ('DedaMyGiftsPage', '_DedaMyGiftsPageState',
                 'DedaGiftNavBadge', '_DedaGiftNavBadgeState', 'DedaGiftInbox'):
        marker = 'class ' + name + ' '
        expected = member(old, marker)
        if name == 'DedaGiftInbox':
            expected = bottom.patch_inbox(expected)
        equal(name, expected, member(new, marker))
    badge = 'deda_stage75_unread_gift_badge.dart'
    equal(badge, bottom.patch_id_badge(read(reference, badge)), read(project, badge))
    for name in ('deda_stage74_id_gift_service.dart', 'deda_official_gift_logo.dart',
                 'deda_gift_recipient_preview.dart'):
        equal(name, read(reference, name), read(project, name))
    # Existing tested inbox lifetime changes were already approved in the profile
    # binder. Reconstruct from the archive, but require the signed 100450 member
    # itself to equal the unmodified, original bound reference first.
    name = 'deda_stage74_hadaya_identifier_section.dart'
    archive = profile.archived_profile_member('lib/' + name)
    original = profile.bind_existing_section_lifetime(archive)
    equal(name + ':100450-original', original, read(reference, name))
    patched = profile.patch_hadaya_archive(archive, (ROOT/'lib'/name).read_text())
    expected = profile.bind_existing_section_lifetime(patched)
    profile.verify_hadaya_section_lifetime(original, expected)
    equal(name, expected, read(project, name))
    # The original bottom binder verifies reachability, account-generation
    # guards and that both gift notification sources are combined only once.
    bottom.verify(new, read(project, badge), home.archive_reference())
    print('PASS_GIFTS_100450_SOURCE_PARITY_ID_DIAMOND_INBOX_BADGES_NO_CLAIM', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--section', choices=['gifts'], required=True)
    args = parser.parse_args()
    reference, project = args.reference.resolve(), args.project.resolve()
    if reference == project or ROOT in reference.parents or ROOT in project.parents:
        raise ValueError('REMAINING_AUDIT_REQUIRES_TWO_DISPOSABLE_ASSEMBLIES')
    gifts(reference, project)
