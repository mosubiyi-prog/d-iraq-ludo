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



def assistant(reference, project):
    old, new = read(reference, 'main.dart'), read(project, 'main.dart')
    original = member(old, home.ASSISTANT_ENTRY)
    expected = original.replace(home.ASSISTANT_ENTRY,
        home.ASSISTANT_ENTRY + '\n    if (!dedaSectionCurrent) return;', 1)
    expected = home.patch_assistant_guide(expected)
    actual = member(new, home.ASSISTANT_ENTRY)
    equal('offline_assistant_guide', expected, actual)
    for marker in ('showModalBottomSheet<void>(', 'showDragHandle: true',
                   'isScrollControlled: true', 'SingleChildScrollView(',
                   "title: dedaText('مستخدم', 'User')",
                   "title: dedaText('صاحب مكان', 'Place owner')",
                   'if (!dedaSectionCurrent) return;', home.ASSISTANT_NEW_AR,
                   home.ASSISTANT_NEW_EN):
        if marker not in actual:
            raise ValueError('ASSISTANT_MISSING:' + marker)
    if actual.count('guideCard(') != 3 or actual.count('steps: [') != 2:
        raise ValueError('ASSISTANT_ORIGINAL_TWO_GUIDES')
    if actual.count('showModalBottomSheet<void>(') != 1:
        raise ValueError('ASSISTANT_DUPLICATE_SHEET')
    if home.visual_signature(original) != home.visual_signature(actual):
        raise ValueError('ASSISTANT_VISUAL_DRIFT')
    # Verify actual assembled destination rather than trusting old help copy.
    settings = member(new, 'class _DedaSettingsPageState ')
    makani = member(new, 'class _DedaMakaniPageState ')
    if 'DedaPreferences.setAccountType(' in settings:
        raise ValueError('ASSISTANT_SETTINGS_OWNER_MODE_CONFLICT')
    if 'DedaPreferences.setAccountType(DedaAccountType.placeOwner)' not in makani:
        raise ValueError('ASSISTANT_OWNER_MODE_DESTINATION_MISSING')
    if 'const OwnerPlacePage()' not in makani:
        raise ValueError('ASSISTANT_OWNER_MANAGEMENT_DESTINATION_MISSING')
    body = member(new, 'class _HomePageState ')
    home.verify_home(body)
    bottom.verify_home(body)
    if body.count('onPressed: openDedaAssistant') != 2:
        raise ValueError('ASSISTANT_PHONE_TABLET_ENTRY_MISSING')
    print('PASS_ASSISTANT_100450_BOTH_GUIDES_VISUALS_ROUTES_OWNER_INSTRUCTION', flush=True)



def support(reference, project):
    import sys
    sys.path.insert(0, str(ROOT/'tools/app_stability'))
    from bind_auth_runtime import body_range
    import bind_stage2_contact_draft_2026_11_24 as contact
    old, new = read(reference, 'main.dart'), read(project, 'main.dart')
    equal('DedaContactPage', member(old, 'class DedaContactPage '),
          member(new, 'class DedaContactPage '))
    baseline = member(old, contact.MARKER)
    current = member(new, contact.MARKER)
    equal('contact_existing_page_plus_draft_scope', contact.patch(baseline), current)
    for marker in ("'code': 'company'", "'code': 'problem'", "'code': 'case'",
                   "'code': 'photo'", 'DedaBackend.submitSupport(',
                   'DedaBackend.mySupportRequests(', 'ImagePicker().pickImage(',
                   'DedaBackend.syncCurrentUserProfile(', "item['adminReply']",
                   'rawImagePaths.take(1)', "data['imagePath']",
                   'DedaSectionState<DedaContactPage>', 'dedaRunSectionVoid(',
                   'dedaSectionCurrent', 'DedaPrivateDataBridge.readString(prefs, _draftKey)',
                   'DedaPrivateDataBridge.write(prefs, _draftKey, null)'):
        if marker not in current:
            raise ValueError('SUPPORT_MISSING:' + marker)
    if home.visual_signature(baseline) != home.visual_signature(current):
        raise ValueError('SUPPORT_CONTACT_VISUAL_DRIFT')
    equal('existing_private_data_bridge_contact_scope',
          contact.patch_bridge(read(reference, contact.BRIDGE)), read(project, contact.BRIDGE))
    team = 'deda_team_page.dart'
    equal(team, read(reference, team), read(project, team))
    team_source = read(project, team)
    if team_source.count('number: ') != 7:
        raise ValueError('SUPPORT_TEAM_ORIGINAL_SEVEN_MEMBERS')
    bg = 'assets/deda_home_bg.jpg'
    if (reference/bg).read_bytes() != (project/bg).read_bytes():
        raise ValueError('SUPPORT_TEAM_BACKGROUND_DRIFT')
    old_backend, new_backend = read(reference, 'deda_backend.dart'), read(project, 'deda_backend.dart')
    for name in ('submitSupport', 'mySupportRequests'):
        def method(src):
            a,z,_,start = body_range(src,name)
            return src[start:z+1]
        equal('backend:' + name, method(old_backend), method(new_backend))
    body = member(new, 'class _HomePageState ')
    home.verify_home(body)
    if body.count('const DedaTeamPage()') != 2 or body.count('DedaContactPage(') != 2:
        raise ValueError('SUPPORT_PHONE_TABLET_ENTRY_DRIFT')
    dash = read(project, 'deda_stage2_isolated_admin_dashboard_2026_11_21.dart')
    for marker in ("collection: 'support_requests'", 'replyToScopedSupport(',
                   'updateScopedSupportStatus(', 'mutateScopedSupportTrash(',
                   'DedaStage2IsolatedSupportTrashPage('):
        if marker not in dash:
            raise ValueError('SUPPORT_ISOLATED_ADMIN_LINK:' + marker)
    # Explicit release blocker: preserve the first-stage no-passive-UID rule.
    # Guest form remains reachable, but a fully signed-out sender cannot
    # be assumed authorized to submit to Firebase. Do not bypass the guard.
    if 'deda-stability-explicit-auth-entry-no-new-uid' not in new_backend:
        raise ValueError('SUPPORT_NO_NEW_UID_GUARD_LOST')
    print('SUPPORT_GUEST_SEND_REQUIRES_EXPLICIT_AUTH_OR_APPROVED_GUEST_TRANSPORT_RELEASE_HOLD', flush=True)
    print('PASS_SUPPORT_100450_CONTACT_TEAM_ADMIN_SOURCE_PARITY_DRAFT_SCOPE', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--section', choices=['gifts', 'assistant', 'support'], required=True)
    args = parser.parse_args()
    reference, project = args.reference.resolve(), args.project.resolve()
    if reference == project or ROOT in reference.parents or ROOT in project.parents:
        raise ValueError('REMAINING_AUDIT_REQUIRES_TWO_DISPOSABLE_ASSEMBLIES')
    {'gifts': gifts, 'assistant': assistant, 'support': support}[args.section](reference, project)
