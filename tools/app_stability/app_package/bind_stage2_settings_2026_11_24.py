"""Settings: retain original four device preference keys and protected routes.
Apply only to the assembled temporary app, after corrected Google integration.
No production auth operation, permission grant, wallet or account data mutation.
"""
import argparse
import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('home_binder', ROOT/'tools/app_stability/app_package/bind_stage2_home_2026_11_24.py')
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)
MARK = 'DEDA_STAGE2_SETTINGS_EXISTING_PREFERENCES_SERIAL'
UI_MARK = 'DEDA_STAGE2_SETTINGS_ORIGINAL_CONTROL_GUARD'

def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError('SETTINGS_SOURCE_STOP:' + label + ':' + str(s.count(old)))
    return s.replace(old, new, 1)

# No new preferences or ownership scope. This serializes the four existing
# device-level controls and commits the in-memory value only after success.
SAVE = '''  // ''' + MARK + '''
  static Future<void> _navigationSettingsTail = Future<void>.value();

  static Future<void> _saveNavigationSetting(
      Future<bool> Function(SharedPreferences) persist, VoidCallback apply) async {
    final previous = _navigationSettingsTail;
    final release = Completer<void>();
    _navigationSettingsTail = release.future;
    try {
      await DedaSectionOperationContext.wait(() => previous);
      final prefs = await DedaSectionOperationContext.wait(() => SharedPreferences.getInstance());
      final saved = await DedaSectionOperationContext.wait(() => persist(prefs));
      if (!saved) throw StateError('navigation-setting-not-persisted');
      apply();
    } finally {
      release.complete();
    }
  }

'''

SETTERS = (
    ('setVoiceEnabled', 'bool enabled', 'navigationVoiceEnabled', 'enabled', 'setBool', '_voiceEnabledKey', 'enabled'),
    ('setSpeechRate', 'double rate', 'speechRate', 'rate', 'setDouble', '_speechRateKey', 'rate'),
    ('setDefaultTravelMode', 'DedaTravelMode mode', 'defaultTravelMode', 'mode', 'setString', '_travelModeKey', 'mode.name'),
    ('setDefaultMapStyle', 'DedaMapStyle style', 'defaultMapStyle', 'style', 'setString', '_mapStyleKey', 'style.name'),
)

def patch_preferences(body):
    if MARK in body:
        raise ValueError('SETTINGS_SOURCE_STOP:already-bound-preferences')
    for name, param, field, value, method, key, stored in SETTERS:
        old = ('  static Future<void> ' + name + '(' + param + ') async {\n'
               '    ' + field + ' = ' + value + ';\n'
               '    final prefs = await SharedPreferences.getInstance();\n'
               '    await prefs.' + method + '(' + key + ', ' + stored + ');\n  }')
        new = ('  static Future<void> ' + name + '(' + param + ') =>\n'
               '      _saveNavigationSetting((prefs) => prefs.' + method + '(' + key + ', ' + stored + '),\n'
               '          () => ' + field + ' = ' + value + ');')
        body = one(body, old, new, name)
    return one(body, '  static Future<void> setVoiceEnabled(', SAVE + '  static Future<void> setVoiceEnabled(', 'existing-settings-lane')

UI = '''  // ''' + UI_MARK + '''
  bool _settingsLogoutPending = false;
  bool _settingsAdminOpening = false;
  double? _settingsSpeechPreview;
  int _settingsSpeechGeneration = 0;
  int _settingsAdminGeneration = 0;
  String? _settingsAdminUid;
  StreamSubscription<User?>? _settingsAdminAuth;

  bool get _settingsCurrent => dedaSectionCurrent && DedaPreferences.isLoggedIn;

  Future<void> _saveSettingsChoice(Future<void> Function() save) async {
    if (!_settingsCurrent || _settingsLogoutPending) return;
    try {
      await dedaRunSectionVoid(() async {
        await DedaSectionOperationContext.wait(save);
      });
    } catch (_) {
      if (_settingsCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dedaText(
          'تعذر حفظ الإعداد. حاول مرة أخرى.', 'Could not save the setting. Try again.'))));
        setState(() {});
      }
    }
  }

  Future<void> _setNavigationVoice(bool value) =>
      _saveSettingsChoice(() => DedaPreferences.setVoiceEnabled(value));
  Future<void> _setTravelMode(DedaTravelMode mode) =>
      _saveSettingsChoice(() => DedaPreferences.setDefaultTravelMode(mode));
  Future<void> _setMapStyle(DedaMapStyle style) =>
      _saveSettingsChoice(() => DedaPreferences.setDefaultMapStyle(style));

  Future<void> _commitSpeechPreview(double value) async {
    if (!_settingsCurrent || _settingsLogoutPending) return;
    final generation = ++_settingsSpeechGeneration;
    await _saveSettingsChoice(() => DedaPreferences.setSpeechRate(value));
    if (_settingsCurrent && generation == _settingsSpeechGeneration) {
      setState(() => _settingsSpeechPreview = null);
    }
  }

  void _invalidateSettingsAdmin() {
    ++_settingsAdminGeneration;
    _settingsAdminUid = null;
    if (_settingsCurrent) setState(() => _adminEntryVisible = false);
  }

  @override
  void dedaOnSectionExpired() {
    ++_settingsAdminGeneration;
    dedaCancelSectionResource(() => _settingsAdminAuth?.cancel());
    _settingsAdminAuth = null;
    super.dedaOnSectionExpired();
  }

  @override
  void dispose() {
    ++_settingsAdminGeneration;
    dedaCancelSectionResource(() => _settingsAdminAuth?.cancel());
    super.dispose();
  }

'''

def callback_region(s, marker):
    if s.count(marker) != 1:
        raise ValueError('SETTINGS_SOURCE_STOP:callback:' + marker)
    a = s.index(marker)
    opening = s.index('{', a + len(marker) - 1)
    ts = home.tokens(s[opening:])
    z = opening + ts[home.pairs(ts, True)[0]][1]
    return opening, z

def patch_ui(body):
    if 'DedaSectionState<DedaSettingsPage>' not in body or UI_MARK in body:
        raise ValueError('SETTINGS_SOURCE_STOP:existing-section')
    original = body
    body = one(body, '  bool _adminEntryVisible = false;', '  bool _adminEntryVisible = false;\n\n' + UI, 'settings-fields')
    body = one(body, '    unawaited(_refreshAdminEntryVisibility());', '''    if (Firebase.apps.isNotEmpty) {
      _settingsAdminAuth = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (!_settingsCurrent) return;
        _invalidateSettingsAdmin();
        unawaited(_refreshAdminEntryVisibility());
      }, onError: (Object _) => _invalidateSettingsAdmin(),
         onDone: _invalidateSettingsAdmin);
    } else {
      unawaited(_refreshAdminEntryVisibility());
    }''', 'refresh-existing-admin-visibility-on-auth')
    # The generated async section scope remains intact. A newer auth event
    # invalidates a slower previous read even if the phone is unchanged.
    a,z = callback_region(body, '  Future<void> _refreshAdminEntryVisibility() async {')
    part = body[a:z+1]
    if ('currentDedaAccountCanSeeAdminEntry(' not in part or
        'setState(() => _adminEntryVisible = allowed);' not in part):
        raise ValueError('SETTINGS_SOURCE_STOP:existing-admin-reader:' + repr(part))
    # Capture the generation outside the existing method's operation wrapper;
    # the actual assembly can use either section or inherited auth guards.
    # Preserve every token of the original operation body.
    part = part[:1] + '\n    if (!_settingsCurrent) return;\n    final generation = ++_settingsAdminGeneration;' + part[1:]
    part = one(part, '    setState(() => _adminEntryVisible = allowed);',
        '    if (!_settingsCurrent || generation != _settingsAdminGeneration) return;\n'
        '    final uid = Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;\n'
        '    setState(() {\n'
        '      _settingsAdminUid = allowed ? uid : null;\n'
        '      _adminEntryVisible = allowed && uid != null;\n'
        '    });', 'only-current-admin-result')
    body = body[:a] + part + body[z+1:]
    body = one(body, 'if (_adminEntryVisible) ...[',
        'if (_adminEntryVisible && _settingsAdminUid != null &&\n'
        '                      Firebase.apps.isNotEmpty &&\n'
        '                      FirebaseAuth.instance.currentUser?.uid == _settingsAdminUid) ...[', 'no-stale-admin-card')
    # Existing logout intent already validates account and auth epoch inside
    # the one auth lane. Only add an entry lock, not another logout path.
    a,z = callback_region(body, '  Future<void> _logoutPersonalAccount() async {')
    part = body[a+1:z]
    if 'logoutIntent.commit' not in part or 'confirmed != true' not in part:
        raise ValueError('SETTINGS_SOURCE_STOP:original-personal-logout-intent')
    body = body[:a+1] + '''
    if (!_settingsCurrent || _settingsLogoutPending || _settingsAdminOpening) return;
    _settingsLogoutPending = true;
    try {''' + part + '''
    } finally {
      _settingsLogoutPending = false;
    }
  ''' + body[z:]
    # Preserve existing admin permission check and both admin routes.
    a,z = callback_region(body, 'onPressed: () async {')
    part = body[a+1:z]
    if 'currentDedaAccountCanSeeAdminEntry(' not in part or 'dedaIsolatedAdminIdentityEnabled' not in part:
        raise ValueError('SETTINGS_SOURCE_STOP:existing-admin-gates')
    # Keep the prior async/section operation intact, including its return
    # paths. Await the original callback inside the one navigation lock.
    # Wait for original route dismissal to release the entry lock; no
    # changes to admin login/auth or route builder arguments.
    ts = home.tokens(part)
    match = home.pairs(ts)
    edits = []
    for i,(word,start,_) in enumerate(ts):
        if word == 'Navigator' and [v[0] for v in ts[i+1:i+4]] == ['.','push','(']:
            end = ts[match[i+3]][2]
            edits.append((start,end))
    if len(edits) != 2:
        raise ValueError('SETTINGS_SOURCE_STOP:two-existing-admin-routes')
    for start,end in reversed(edits):
        part = part[:start] + 'await ' + part[start:end] + part[end:]
    body = body[:a+1] + '''
    if (!_settingsCurrent || _settingsAdminOpening || _settingsLogoutPending ||
        !_adminEntryVisible) return;
    _settingsAdminOpening = true;
    try {
      await (() async {''' + part + '''
      })();
    } finally {
      _settingsAdminOpening = false;
      if (_settingsCurrent) unawaited(_refreshAdminEntryVisibility());
    }
  ''' + body[z:]
    # Existing switch and chips are guarded async callbacks. Reuse them.
    for old,new in (('DedaPreferences.setVoiceEnabled(', '_setNavigationVoice('),
                    ('DedaPreferences.setDefaultTravelMode(', '_setTravelMode('),
                    ('DedaPreferences.setDefaultMapStyle(', '_setMapStyle(')):
        # The helper's original setter call must stay intact.
        a = body.index('  Widget _sectionTitle(')
        body = body[:a] + one(body[a:], old, new, 'existing-control:'+old)
    body = one(body, 'value: DedaPreferences.speechRate\n',
        'value: (_settingsSpeechPreview ?? DedaPreferences.speechRate)\n', 'speech-preview-value')
    body = one(body, 'DedaPreferences.speechRate.toStringAsFixed(2)',
        '(_settingsSpeechPreview ?? DedaPreferences.speechRate).toStringAsFixed(2)', 'speech-preview-label')
    body = one(body, '''                              setState(
                                  () => DedaPreferences.speechRate = value);''',
        '''                              if (!_settingsCurrent || _settingsLogoutPending) return;
                              ++_settingsSpeechGeneration;
                              setState(() => _settingsSpeechPreview = value);''', 'speech-preview-only-in-current-widget')
    body = one(body, 'DedaPreferences.setSpeechRate(value);\n                            },',
        'unawaited(_commitSpeechPreview(value));\n                            },', 'speech-save-existing-value')
    body = one(body, '''                        Geolocator.openAppSettings();''',
        '''                        if (!_settingsCurrent || _settingsLogoutPending) return;
                        unawaited(Geolocator.openAppSettings().then<void>((_) {},
                            onError: (Object _) {
                              if (_settingsCurrent) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dedaText(
                                  'تعذر فتح إعدادات الموقع.', 'Could not open location settings.'))));
                              }
                            }));''', 'original-os-settings-route')
    if home.visual_signature(body) != home.visual_signature(original):
        raise ValueError('SETTINGS_SOURCE_STOP:visual-literal-change')
    verify_ui(body)
    return body

def verify_ui(body):
    for marker in (UI_MARK, 'DedaSectionState<DedaSettingsPage>', 'DedaStage2GoogleAccessCard(',
                   'onFreshGoogleIdentity: _onStage2FreshGoogleIdentity', 'onTap: _logoutPersonalAccount,',
                   'logoutIntent.commit(isCurrent: () => mounted)', 'confirmed != true',
                   '_settingsLogoutPending = true;', '_settingsAdminOpening = true;',
                   'generation != _settingsAdminGeneration', 'FirebaseAuth.instance.authStateChanges()',
                   'FirebaseAuth.instance.currentUser?.uid == _settingsAdminUid',
                   'DedaBackend.currentDedaAccountCanSeeAdminEntry(', 'dedaIsolatedAdminIdentityEnabled',
                   'DedaAdminLoginPage(', 'DedaAdminDashboardPage(', 'Geolocator.openAppSettings()',
                   '_setNavigationVoice(', '_setTravelMode(', '_setMapStyle(', '_commitSpeechPreview(value)',
                   'min: 0.35,', 'max: 0.65,', 'divisions: 6,',
                   'DedaTravelMode.values.map', 'DedaMapStyle.values.map'):
        if marker not in body:
            raise ValueError('SETTINGS_VERIFY_UI:' + marker)
    order = [body.index(s) for s in ("'الصوت والملاحة'", "'وسيلة التنقل الافتراضية'",
              "'نوع الخريطة الافتراضي'", "'الموقع'", "'الإدارة'",
              'DedaStage2GoogleAccessCard(', 'onTap: _logoutPersonalAccount,')]
    if order != sorted(order) or body.count('DedaStage2GoogleAccessCard(') != 1:
        raise ValueError('SETTINGS_VERIFY:approved-control-order')

def verify(main):
    a,z = home.span(main, 'class _DedaSettingsPageState ')
    verify_ui(main[a:z])
    a,z = home.span(main, 'class DedaPreferences ')
    pref = main[a:z]
    for marker in (MARK, 'if (!saved) throw StateError', 'release.complete();',
                   "'deda_voice_enabled_v1'", "'deda_speech_rate_v1'",
                   "'deda_default_travel_mode_v1'", "'deda_default_map_style_v1'"):
        if marker not in pref:
            raise ValueError('SETTINGS_VERIFY_PREF:' + marker)
    for name, param, field, value, method, key, stored in SETTERS:
        if pref.count('_saveNavigationSetting((prefs) => prefs.' + method + '(' + key + ', ' + stored + ')') != 1:
            raise ValueError('SETTINGS_VERIFY_PREF:original-key:' + key)
    if main.count('DedaStage2GoogleAccessCard(') != 1:
        raise ValueError('SETTINGS_VERIFY:duplicate-google-card')
    a,z = home.home_span(main)
    if 'const DedaSettingsPage()' not in main[a:z]:
        raise ValueError('SETTINGS_VERIFY:unreachable-from-home')
    a,z = home.span(main, 'class _DedaSettingsPageState ')
    a0,z0 = home.span(home.archive_reference(), 'class _DedaSettingsPageState ')
    old = home.archive_reference()[a0:z0]
    if home.visual_signature(main[a:z]) != home.visual_signature(old):
        raise ValueError('SETTINGS_VERIFY:original-colors-and-icons')

def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('SETTINGS_DO_NOT_MODIFY_REPOSITORY')
    path = project/'lib/main.dart'
    main = path.read_text()
    if not verify_only:
        a,z = home.span(main, 'class DedaPreferences ')
        main = main[:a] + patch_preferences(main[a:z]) + main[z:]
        a,z = home.span(main, 'class _DedaSettingsPageState ')
        main = main[:a] + patch_ui(main[a:z]) + main[z:]
    verify(main)
    if not verify_only:
        path.write_text(main)
    print('PASS_STAGE2_SETTINGS_ORIGINAL_CONTROLS_GOOGLE_ACTUAL_LOGOUT_ADMIN_LOCATION_PREFERENCES_NO_ACTIVATION')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bind(args.project, args.verify_only)
