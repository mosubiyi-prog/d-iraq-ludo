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


# The ORIGINAL profile editor is a different page from the My Store route.
# Its already-staged Point09 appearance setter is account-scoped: reuse it,
# never create a second appearance writer, inventory, wallet, or UID.
EDITOR = 'class _DedaEditProfilePageState'
EDITOR_MARK = '// DEDA_STAGE2_PROFILE_EDITOR_OWNER_CHECK_2026_11_23'
EDITOR_FIELDS = """  // DEDA_STAGE2_PROFILE_EDITOR_OWNER_CHECK_2026_11_23
  late final String _dedaStage2EditPhone;
  late final DedaAccountType? _dedaStage2EditAccountType;
  late final String? _dedaStage2EditUid;
  late final bool _dedaStage2EditFirebaseReady;
  StreamSubscription<User?>? _dedaStage2EditAuthSubscription;

  bool _dedaStage2SameEditingAccount() =>
      mounted &&
      DedaPreferences.isLoggedIn &&
      DedaPreferences.phone == _dedaStage2EditPhone &&
      DedaPreferences.accountType == _dedaStage2EditAccountType &&
      Firebase.apps.isNotEmpty == _dedaStage2EditFirebaseReady &&
      (Firebase.apps.isEmpty
          ? null : FirebaseAuth.instance.currentUser?.uid) ==
          _dedaStage2EditUid;

"""
EDITOR_INIT = """    super.initState();
    _dedaStage2EditPhone = DedaPreferences.phone;
    _dedaStage2EditAccountType = DedaPreferences.accountType;
    _dedaStage2EditFirebaseReady = Firebase.apps.isNotEmpty;
    _dedaStage2EditUid = Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid;
    if (_dedaStage2EditFirebaseReady) {
      _dedaStage2EditAuthSubscription =
          FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted) setState(() {});
      });
    }
    _name = TextEditingController(text: DedaPreferences.userName);"""
EDITOR_SAVE_OPEN = """  Future<void> _save() async {
    // The editor may outlive the public owner: never start stale writes.
    if (!_dedaStage2SameEditingAccount()) {
      if (mounted) setState(() => _error = dedaText(
        'تغيّر الحساب. أعد فتح تعديل الملف للحساب الحالي.',
        'Account changed. Reopen Edit Profile for the current account.'));
      return;
    }"""
EDITOR_SAVE_BETWEEN = """      await DedaPreferences.setUserName(cleanName);
      // Stop before the second (appearance) write when Auth rotated while
      // the original name setter awaited; do not report a stale success.
      if (!_dedaStage2SameEditingAccount()) return;"""
EDITOR_SAVE_END = """      if (!_dedaStage2SameEditingAccount()) return;
      Navigator.pop(context, true);"""
EDITOR_DISPOSE = """  @override
  void dispose() {
    _dedaStage2EditAuthSubscription?.cancel();
    _name.dispose();"""
EDITOR_BUILD = """  @override
  Widget build(BuildContext context) {
    if (!_dedaStage2SameEditingAccount()) {
      return Scaffold(
        appBar: AppBar(title: Text(dedaText('تعديل الملف', 'Edit Profile'))),
        body: Center(child: Text(dedaText(
          'تغيّر الحساب. أعد فتح تعديل الملف للحساب الحالي.',
          'Account changed. Reopen Edit Profile for the current account.',
        ), textAlign: TextAlign.center)),
      );
    }
    return Scaffold("""


def editor_span(main: str) -> tuple[int, int]:
    if main.count(EDITOR) != 1:
        # The compiled source can add a mixin or repackage the editor.
        # Report exact class candidates; NEVER select a different page.
        import re
        nearby = re.findall(r'(?m)^class [^\n]*(?:Edit|Profile)[^\n]*', main)
        raise ValueError(
            'PROFILE_SAFE_STOP:original-editor-class-count=' +
            str(main.count(EDITOR)) + ':class_candidates=' +
            repr(nearby[:20]))
    start = main.index(EDITOR)
    class_header = main[start:main.find('{', start) + 1]
    if 'extends State<DedaEditProfilePage>' not in class_header:
        raise ValueError('PROFILE_SAFE_STOP:editor-inheritance-changed')
    end = main.find('\nclass ', start + len(EDITOR))
    if end < 0:
        raise ValueError('PROFILE_SAFE_STOP:original-editor-next-class-not-found')
    return start, end


def patch_original_editor(main: str) -> str:
    start, end = editor_span(main)
    editor = main[start:end]
    if EDITOR_MARK in editor:
        raise ValueError('PROFILE_SAFE_STOP:editor-already-bound')
    for label, old, new in (
        ('existing-saving-field',
         '  bool _saving = false;', EDITOR_FIELDS + '  bool _saving = false;'),
        ('real-profile-init',
         '    super.initState();\n    _name = TextEditingController(text: DedaPreferences.userName);',
         EDITOR_INIT),
        ('original-dispose',
         '  @override\n  void dispose() {\n    _name.dispose();',
         EDITOR_DISPOSE),
        ('original-save',
         '  Future<void> _save() async {', EDITOR_SAVE_OPEN),
        ('name-save',
         '      await DedaPreferences.setUserName(cleanName);',
         EDITOR_SAVE_BETWEEN),
        ('before-original-success',
         '      Navigator.pop(context, true);',
         EDITOR_SAVE_END),
        ('original-build',
         '  @override\n  Widget build(BuildContext context) {\n    return Scaffold(',
         EDITOR_BUILD),
    ):
        editor = once(editor, old, new, 'editor-' + label)
    # Recheck around the original Point09 account-scoped appearance writer.
    # No new setter is introduced; this guard denies stale save continuation.
    setter = '      await DedaPreferences.setProfileAppearance('
    if editor.count(setter) != 1:
        raise ValueError('PROFILE_SAFE_STOP:original-appearance-call-drift')
    editor = once(editor, setter,
                  '      if (!_dedaStage2SameEditingAccount()) return;\n' + setter,
                  'editor-before-appearance')
    main = main[:start] + editor + main[end:]
    verify_original_editor(main)
    return main


def verify_original_editor(main: str):
    start, end = editor_span(main)
    editor = main[start:end]
    conditions = {
        'one-editor-owner-guard': editor.count(EDITOR_MARK) == 1,
        'same-phone': 'DedaPreferences.phone == _dedaStage2EditPhone' in editor,
        'same-type': 'DedaPreferences.accountType == _dedaStage2EditAccountType' in editor,
        'same-uid': 'FirebaseAuth.instance.currentUser?.uid' in editor,
        'auth-listener': 'authStateChanges().listen' in editor,
        'listener-disposed': '_dedaStage2EditAuthSubscription?.cancel();' in editor,
        'guard-before-name': editor.index('if (!_dedaStage2SameEditingAccount())') <
            editor.index('await DedaPreferences.setUserName(cleanName);'),
        'guard-between-saves': 'await DedaPreferences.setUserName(cleanName);\n' in editor and
            editor.count('if (!_dedaStage2SameEditingAccount()) return;') >= 3,
        'single-original-name-writer': editor.count('await DedaPreferences.setUserName(cleanName);') == 1,
        'single-original-appearance-writer': editor.count('await DedaPreferences.setProfileAppearance(') == 1,
        'original-edit-gallery-retained': 'DedaFramedAvatar(' in editor,
        'original-save-page-retained': 'Navigator.pop(context, true);' in editor,
    }
    for label, verified in conditions.items():
        if not verified:
            raise ValueError('PROFILE_VERIFY_FAILED:editor-' + label)


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
    main = patch_original_editor(main)
    verify(main, old_store)
    return main


def verify(main: str, old_store: str):
    verify_original_editor(main)
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
    if ('DEDA_100377_POINT09_APPEARANCE_ASYNC_ACCOUNT_SCOPE' not in main or
            '_profileAvatarKey(savePhone)' not in main):
        raise ValueError('PROFILE_SAFE_STOP:prior-appearance-account-guard-missing')
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
