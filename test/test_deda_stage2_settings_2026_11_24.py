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

    def test_repository_write_refused(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
