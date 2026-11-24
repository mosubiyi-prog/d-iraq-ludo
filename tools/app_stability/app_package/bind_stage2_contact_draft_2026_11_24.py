"""Scope the existing contact draft locally, without changing support transport.
Keep the legacy value intact; only a matching signed-in account can read it.
A guest draft with no proven owner is not automatically exposed to a new user.
"""
import argparse
from pathlib import Path
import bind_stage2_home_2026_11_24 as home

ROOT = Path(__file__).resolve().parents[3]
MARKER = 'class _DedaContactPageState '
FENCE = 'DEDA_STAGE2_CONTACT_DRAFT_ACCOUNT_SCOPE'

FIELDS = '''  // DEDA_STAGE2_CONTACT_DRAFT_ACCOUNT_SCOPE
  static const String _legacyDraftKey = 'deda_contact_draft_v1';
  late final String? _draftKey;
  late final int _contactDraftEpoch;
  late final bool _contactDraftSignedIn;

  static String? _draftStorageKey(bool signedIn, String phone) {
    if (!signedIn) return 'deda_contact_draft_v1:guest';
    final account = DedaBackend.accountKeyForPhone(phone);
    if (account.isEmpty) return null;
    return 'deda_contact_draft_v1:account:$account';
  }

  bool get _contactDraftCurrent =>
      dedaSectionCurrent &&
      _contactDraftEpoch == DedaPreferences.stabilityAccountEpoch &&
      _contactDraftSignedIn == DedaPreferences.isLoggedIn &&
      _draftKey == _draftStorageKey(DedaPreferences.isLoggedIn, DedaPreferences.phone);
'''

LOAD = '''      final key = _draftKey;
      if (key == null || !_contactDraftCurrent) return;
      var raw = prefs.getString(key);
      if (raw == null && _contactDraftSignedIn) {
        final legacy = prefs.getString(_legacyDraftKey);
        if (legacy != null && legacy.isNotEmpty) {
          final data = jsonDecode(legacy);
          if (data is Map<String, dynamic>) {
            final savedAccount = DedaBackend.accountKeyForPhone(
                (data['phone'] ?? '').toString());
            final currentAccount = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
            if (savedAccount.isNotEmpty && savedAccount == currentAccount) {
              raw = legacy;
            }
          }
        }
      }
'''


def patch(body):
    if FENCE in body or 'DedaSectionState<DedaContactPage>' not in body:
        raise ValueError('CONTACT_SOURCE_STOP:missing-original-section')
    original = body
    def replace(old, new, label):
        nonlocal body
        body = home.one(body, old, new, 'contact:' + label)
    replace("  static const String _draftKey = 'deda_contact_draft_v1';\n",
            FIELDS, 'single-old-draft-key')
    replace('    super.initState();\n', '''    super.initState();
    _contactDraftEpoch = DedaPreferences.stabilityAccountEpoch;
    _contactDraftSignedIn = DedaPreferences.isLoggedIn;
    _draftKey = _draftStorageKey(_contactDraftSignedIn, DedaPreferences.phone);
''', 'capture-on-open')
    replace('      final raw = prefs.getString(_draftKey);\n', LOAD, 'draft-load')
    replace('  Future<void> _saveDraft() async {',
            '''  Future<void> _saveDraft() async {
    if (_draftKey == null || !_contactDraftCurrent || _saving || _submitting) return;''',
            'save-entry')
    replace('        _draftKey,\n', '        _draftKey!,\n', 'same-draft-write')
    replace('  Future<void> _prepareMessage() async {',
            '''  Future<void> _prepareMessage() async {
    if (_draftKey == null || !_contactDraftCurrent || _saving || _submitting) return;''',
            'submit-entry')
    # Leave the legacy key unchanged. An empty scoped draft prevents the
    # old, already-sent legacy draft from resurfacing on the next opening.
    replace('prefs.remove(_draftKey)', "prefs.setString(_draftKey!, '')",
            'clear-only-current-draft')
    # Preserve the original history, transport, single image, and appearance.
    if home.visual_signature(body) != home.visual_signature(original):
        raise ValueError('CONTACT_SOURCE_STOP:visual-drift')
    return body


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('CONTACT_REQUIRES_DISPOSABLE_ASSEMBLY')
    path = project/'lib/main.dart'
    source = path.read_text(encoding='utf-8')
    a,z = home.span(source, MARKER)
    result = patch(source[a:z])
    path.write_text(source[:a] + result + source[z:], encoding='utf-8')
    print('PASS_CONTACT_LOCAL_DRAFT_SCOPE_LEGACY_RETAINED_NO_TRANSPORT_CHANGE', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    bind(parser.parse_args().project)
