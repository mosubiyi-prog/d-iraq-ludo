"""Preserve the original private-data bridge and scope only contact drafts."""
import argparse
from pathlib import Path
import bind_stage2_home_2026_11_24 as home

ROOT = Path(__file__).resolve().parents[3]
MARKER = 'class _DedaContactPageState '
BRIDGE = 'deda_private_data_bridge.dart'
FENCE = 'DEDA_STAGE2_CONTACT_DRAFT_ACCOUNT_SCOPE'


def patch(body):
    if 'DedaSectionState<DedaContactPage>' not in body:
        raise ValueError('CONTACT_MISSING_ORIGINAL_SECTION')
    for anchor in ('DedaPrivateDataBridge.readString(prefs, _draftKey)',
                   'DedaPrivateDataBridge.write(prefs,\n        _draftKey,',
                   'DedaPrivateDataBridge.write(prefs, _draftKey, null)'):
        if body.count(anchor) != 1:
            raise ValueError('CONTACT_ORIGINAL_BRIDGE_REQUIRED:' + anchor)
    body = home.one(body, '      if (raw == null || raw.isEmpty) return;',
                    '      if (!dedaSectionCurrent || raw == null || raw.isEmpty) return;',
                    'contact:post-read-guard')
    for name in ('_saveDraft', '_prepareMessage'):
        anchor = '  Future<void> ' + name + '() async {'
        body = home.one(body, anchor, anchor +
            '\n    if (!dedaSectionCurrent || _saving || _submitting) return;',
            'contact:single-operation:' + name)
    return body


HELPER = '''  // DEDA_STAGE2_CONTACT_DRAFT_ACCOUNT_SCOPE
  static const _contactKey = 'deda_contact_draft_v1';
  static String? _contactNativeKey() {
    if (!DedaPreferences.isLoggedIn) return '$_contactKey:guest';
    final account = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
    return account.isEmpty ? null : '$_contactKey:account:$account';
  }

  static Object? _nativeRead(SharedPreferences prefs, String key) {
    if (key != _contactKey) return prefs.get(key);
    final scoped = _contactNativeKey();
    if (scoped == null) return null;
    if (prefs.containsKey(scoped)) return prefs.get(scoped);
    if (!DedaPreferences.isLoggedIn) return null;
    final legacy = prefs.getString(_contactKey);
    if (legacy == null || legacy.isEmpty) return null;
    try {
      final data = jsonDecode(legacy);
      if (data is! Map<String, dynamic>) return null;
      final saved = DedaBackend.accountKeyForPhone((data['phone'] ?? '').toString());
      final current = DedaBackend.accountKeyForPhone(DedaPreferences.phone);
      if (saved.isNotEmpty && saved == current) return legacy;
    } catch (_) { /* Preserve malformed legacy data without exposing it. */ }
    return null;
  }

'''


def patch_bridge(source):
    if FENCE in source:
        raise ValueError('CONTACT_DUPLICATE_BRIDGE')
    def replace(old,new,label):
        nonlocal source
        source = home.one(source,old,new,'contact-bridge:'+label)
    replace("import 'dart:async';", "import 'dart:async';\nimport 'dart:convert';", 'json')
    replace('  static Future<Object?> read(SharedPreferences prefs, String key) async {',
            HELPER + '  static Future<Object?> read(SharedPreferences prefs, String key) async {', 'helper')
    replace('if (!dedaPrivateDataEnabled || !DedaPreferences.isLoggedIn) return prefs.get(key);',
            'if (!dedaPrivateDataEnabled || !DedaPreferences.isLoggedIn) return _nativeRead(prefs, key);', 'local')
    replace('if (!owner.current()) return prefs.get(key);',
            'if (!owner.current()) return _nativeRead(prefs, key);', 'offline')
    replace('return bundle == null ? prefs.get(key) : bundle.fields[field];',
            'return bundle == null ? _nativeRead(prefs, key) : bundle.fields[field];', 'fallback')
    replace("      'deda_personal_places_v1', 'deda_contact_draft_v1'].every((k) => !prefs.containsKey(k));",
            "      'deda_personal_places_v1', 'deda_contact_draft_v1'].every((k) => !prefs.containsKey(k)) &&\n"
            "        (_contactNativeKey() == null || !prefs.containsKey(_contactNativeKey()!));", 'new-device')
    replace('  static Future<bool> _nativeWrite(SharedPreferences prefs, String key, Object? value) {',
            '''  static Future<bool> _nativeWrite(SharedPreferences prefs, String key, Object? value) {
    if (key == _contactKey) {
      final scoped = _contactNativeKey();
      if (scoped == null) throw StateError('contact-draft-account-required');
      if (value != null && value is! String) throw ArgumentError('contact-draft-string-required');
      // A scoped tombstone prevents an already-sent legacy draft reappearing.
      return prefs.setString(scoped, (value as String?) ?? '');
    }''', 'native-write')
    replace("      for (final key in ['deda_favorites_v1', 'deda_recent_v1', 'deda_personal_places_v1', 'deda_contact_draft_v1']) {\n"
            '        fields[_logical(key, owner.account)!] = prefs.get(key);',
            "      for (final key in ['deda_favorites_v1', 'deda_recent_v1', 'deda_personal_places_v1', 'deda_contact_draft_v1']) {\n"
            '        fields[_logical(key, owner.account)!] = _nativeRead(prefs, key);', 'explicit-backup')
    return source


def bind(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('CONTACT_REQUIRES_DISPOSABLE_ASSEMBLY')
    path = project/'lib/main.dart'
    source = path.read_text(encoding='utf-8')
    a,z = home.span(source, MARKER)
    result = patch(source[a:z])
    bridge = project/'lib'/BRIDGE
    revised = patch_bridge(bridge.read_text(encoding='utf-8'))
    path.write_text(source[:a] + result + source[z:], encoding='utf-8')
    bridge.write_text(revised, encoding='utf-8')
    print('PASS_CONTACT_EXISTING_PRIVATE_BRIDGE_SCOPED_LOCAL_FALLBACK_NO_TRANSPORT_CHANGE', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    bind(parser.parse_args().project)
