import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('settings', ROOT/'tools/app_stability/app_package/bind_stage2_settings_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class SettingsSourceTests(unittest.TestCase):
    def test_protected_preferences_keep_original_four_keys_and_confirm_writes(self):
        raw = mod.home.archive_reference()
        a,z = mod.home.span(raw, 'class DedaPreferences ')
        original = raw[a:z]
        changed = mod.patch_preferences(original)
        for name, param, field, value, method, key, stored in mod.SETTERS:
            self.assertIn('_saveNavigationSetting((prefs) => prefs.' + method + '(' + key + ', ' + stored + ')', changed)
        self.assertIn('if (!saved) throw StateError', changed)
        self.assertIn('release.complete();', changed)
        for key in ('_voiceEnabledKey','_speechRateKey','_travelModeKey','_mapStyleKey'):
            self.assertEqual(original.count(key), changed.count(key))
        with self.assertRaises(ValueError):
            mod.patch_preferences(changed)

    def test_original_settings_is_separate_from_legacy_account_hub(self):
        raw = mod.home.archive_reference()
        a,z = mod.home.span(raw, 'class _DedaSettingsPageState ')
        settings = raw[a:z]
        for marker in ('_logoutPersonalAccount()', 'onTap: _logoutPersonalAccount,',
                       'DedaBackend.currentDedaAccountCanSeeAdminEntry(', 'Geolocator.openAppSettings()',
                       'min: 0.35,', 'max: 0.65,', 'DedaTravelMode.values.map', 'DedaMapStyle.values.map'):
            self.assertIn(marker, settings)
        self.assertNotIn('onPressed: _logout,', settings)
        self.assertIn('const DedaSettingsPage()', raw)
        self.assertIn('onPressed: _logout,', raw)

    def test_actual_existing_stage3_wrapper_passes_generation_to_original_reader(self):
        raw = mod.home.archive_reference()
        a,z = mod.home.span(raw, 'class _DedaSettingsPageState ')
        settings = raw[a:z].replace(
            '  Future<void> _refreshAdminEntryVisibility() async {',
            '  Future<void> _refreshAdminEntryVisibilityOriginal() async {', 1)
        script = (ROOT/'tools/app_stability/app_package/bind_session_rescue_stage3_100441.py').read_text()
        start = script.index('"""  Future<void> _refreshAdminEntryVisibility() async {') + 3
        end = script.index('  Widget _sectionTitle(String text) {"""', start)
        wrapper = script[start:end]
        settings = settings.replace('  Widget _sectionTitle(String text) {',
                                    wrapper + '  Widget _sectionTitle(String text) {', 1)
        changed = mod.patch_admin_refresh(settings)
        self.assertEqual(changed.count('await _refreshAdminEntryVisibilityOriginal(generation);'), 2)
        self.assertIn('rescue?.mayRecheckAdminGateway == true', changed)
        self.assertIn('generation != _settingsAdminGeneration', changed)
        self.assertIn('DedaBackend.currentDedaAccountCanSeeAdminEntry(', changed)

    def test_100413_single_gateway_optimization_is_preserved(self):
        source = (ROOT/'tools/app_stability/app_package/bind_weekly_100413_owner_id_admin_response.py').read_text()
        a = source.index('"""final gateAllowed = _adminEntryVisible &&') + 3
        z = source.index('"""', a)
        actual = source[a:z] + '''
        if (dedaIsolatedAdminIdentityEnabled) {
          DedaAdminLoginPage();
        }
        final isAdmin = await DedaBackend.currentUserIsAdmin();
        await DedaBackend.currentAdminSessionMatchesDedaEntry(phone: phone);
        '''
        changed = mod.patch_admin_tap_gate(actual)
        self.assertIn('FirebaseAuth.instance.currentUser?.uid == _settingsAdminUid', changed)
        self.assertNotIn('currentDedaAccountCanSeeAdminEntry(', changed)
        self.assertIn('currentUserIsAdmin()', changed)
        with self.assertRaises(ValueError):
            mod.patch_admin_tap_gate(actual + 'currentDedaAccountCanSeeAdminEntry(')

    def test_repository_write_refused(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
