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
    old_body = member(old, 'class _HomePageState ')
    for marker in ('const DedaTeamPage()', 'DedaContactPage('):
        # Match the actual assembled 100450 entries; do not assume that an
        # app-bar action shared across layouts must appear twice in Dart.
        count = old_body.count(marker)
        if count == 0 or body.count(marker) != count:
            raise ValueError('SUPPORT_HOME_ENTRY_DRIFT:' + marker)
        print('SUPPORT_HOME_ENTRY_PARITY', marker, count, flush=True)
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



def login(reference, project):
    import hashlib
    old, new = read(reference, 'main.dart'), read(project, 'main.dart')
    for name in ('LoginPage', '_LoginPageState'):
        marker = 'class ' + name + ' '
        equal('login:' + name, member(old, marker), member(new, marker))
    first = member(new, 'class _LoginPageState ')
    for marker in ("assets/deda_login_bg.jpg", "DedaSmartSecondStageAccountPage(",
                   "_buildExistingAccountForm(", "DedaExistingAccountSignInPage(",
                   "DedaPinAuth.createAccount(", "DedaPreferences.saveLogin(",
                   "new-owner-server-readback-not-proven"):
        if marker not in first:
            raise ValueError('LOGIN_REQUIRED_SOURCE_MISSING:' + marker)
    for marker, count in (('DedaSmartSecondStageAccountPage(', 1),
                          ('DedaExistingAccountSignInPage(', 1),
                          ('Widget _buildExistingAccountForm(', 1)):
        if first.count(marker) != count:
            raise ValueError('LOGIN_DUPLICATE_ENTRY:' + marker)
    # Compare every byte of the three original login artworks in the two
    # actual assemblies. The exact embedded hero and screen layout are
    # covered by the entire LoginPageState equality above.
    for name in ('deda_login_bg.jpg', 'deda_login_reference.jpg',
                 'deda_login_reference_exact.b64'):
        a, b = reference/'assets'/name, project/'assets'/name
        if a.read_bytes() != b.read_bytes():
            raise ValueError('LOGIN_ARTWORK_DRIFT:' + name)
        print('LOGIN_ARTWORK_SHA256', name, hashlib.sha256(b.read_bytes()).hexdigest(), flush=True)
    if "assets/deda_login_bg.jpg" not in (project/'pubspec.yaml').read_text():
        # A directory-level asset declaration is also legitimate.
        if 'assets/' not in (project/'pubspec.yaml').read_text():
            raise ValueError('LOGIN_BACKGROUND_NOT_REGISTERED')
    second = 'deda_step2_smart_second_stage_account_page_100439.dart'
    equal('login:smart-second-stage', read(reference, second), read(project, second))
    existing = 'deda_step2_existing_account_signin_page.dart'
    expected = read(reference, existing)
    for before, after in (
        ("    this.initialPhone,\n",
         "    this.initialPhone,\n    this.sessionOnly = false,\n"),
        ("  final String? initialPhone;\n",
         "  final String? initialPhone;\n  // The 100454 original-phone flow repairs Firebase Auth, NOT user data.\n  final bool sessionOnly;\n"),
        ("              const Text('تسجيل الدخول بحسابك السابق',\n",
         "              Text(widget.sessionOnly\n                  ? 'تفعيل جلسة حسابي الأصلي'\n                  : 'تسجيل الدخول بحسابك السابق',\n"),
        ("                title: const Text('أطلب استرجاع حسابي السابق وبياناته'),\n                subtitle: const Text(\n                  'لا يتم نقل أو تصفير أي بيانات قبل التحقق من مصدرها '\n                  'على الخادم. احتفظ بالهاتف القديم لحين نجاح الفحص.'),",
         "                title: Text(widget.sessionOnly\n                    ? 'أوافق على التحقق من هوية حسابي الأصلي'\n                    : 'أطلب استرجاع حسابي السابق وبياناته'),\n                subtitle: Text(widget.sessionOnly\n                    ? 'تفعيل جلسة Firebase الأصلية فقط بعد إثبات UID على الخادم. '\n                      'لا ننشئ حساباً جديداً ولا نسترجع أو ننقل أي بيانات.'\n                    : 'لا يتم نقل أو تصفير أي بيانات قبل التحقق من مصدرها '\n                      'على الخادم. احتفظ بالهاتف القديم لحين نجاح الفحص.'),"),
        ("                child: Text(_busy ? 'جارٍ فحص الاسترجاع...' :\n                    'التحقق واسترجاع حسابي'),",
         "                child: Text(_busy\n                    ? (widget.sessionOnly ? 'جارٍ التحقق من الجلسة...' : 'جارٍ فحص الاسترجاع...')\n                    : (widget.sessionOnly ? 'تحقق وفعّل الجلسة الأصلية' : 'التحقق واسترجاع حسابي')),"),
    ):
        expected = home.one(expected, before, after, 'login:historical-session-only-mode')
    equal('login:existing-account-with-preserved-session-only-mode', expected, read(project, existing))
    # Keep the release barrier explicit. A staged Google principal is not
    # yet an enrolled DEDA account, and the legacy PIN guardian is not
    # evidence of successful authentication after a change of handset.
    google = read(project, 'deda_stable_google_login_2026_11_21.dart')
    if "'DEDA_STABILITY_GOOGLE_LOGIN', defaultValue: false" not in google:
        raise ValueError('LOGIN_UNAPPROVED_GOOGLE_ACTIVATION')
    if 'deda-stability-original-login-no-anonymous-uid' not in read(project, 'deda_pin_auth.dart'):
        raise ValueError('LOGIN_PASSIVE_UID_GUARD_LOST')
    print('LOGIN_EXISTING_ACCOUNT_AND_GOOGLE_DURABLE_ENROLLMENT_RELEASE_HOLD', flush=True)
    print('PASS_LOGIN_100450_ORIGINAL_FIRST_STAGE_ARTWORK_SECOND_STAGE_SINGLE_DELEGATE', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    parser.add_argument('project', type=Path)
    parser.add_argument('--section', choices=['gifts', 'assistant', 'support', 'login'], required=True)
    args = parser.parse_args()
    reference, project = args.reference.resolve(), args.project.resolve()
    if reference == project or ROOT in reference.parents or ROOT in project.parents:
        raise ValueError('REMAINING_AUDIT_REQUIRES_TWO_DISPOSABLE_ASSEMBLIES')
    {'gifts': gifts, 'assistant': assistant, 'support': support, 'login': login}[args.section](reference, project)
