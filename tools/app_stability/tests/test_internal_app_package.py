"""Private APK input/export boundaries. No Flutter, signing keys or network."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'tools/app_stability/app_package'/f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

prepare, verify = load('prepare'), load('verify')

class InternalPackageTest(unittest.TestCase):
    def test_financial_activation_and_server_automation_cannot_be_enabled_by_variant(self):
        for variant in ('control', 'candidate'):
            flags = prepare.flags(variant)
            self.assertFalse(flags['DEDA_STABILITY_PROGRESS_BACKUP_PILOT'])
            self.assertFalse(flags['DEDA_SERVER_AUTOMATIONS_LIVE'])
            self.assertTrue(flags['DEDA_STABILITY_STARTUP_METRICS'])
        self.assertFalse(prepare.flags('control')['DEDA_STABILITY_AUTH_RUNTIME'])
        self.assertTrue(prepare.flags('candidate')['DEDA_STABILITY_AUTH_RUNTIME'])
        with self.assertRaises(ValueError):
            prepare.flags('production')

    def test_original_manifest_mapping_is_anchored_and_refuses_reapplication(self):
        ids = prepare.known_admob_ids()
        original = f'<meta-data android:value="{ids["TEST_APP_ID"]}" />'
        actual = prepare.switch_manifest_id(original)
        self.assertIn(ids['REAL_APP_ID'], actual)
        for invalid in (actual, original+original, '<manifest/>'):
            with self.assertRaises(ValueError):
                prepare.switch_manifest_id(invalid)

    def test_repository_and_unprepared_paths_cannot_be_overwritten(self):
        for path in (ROOT, ROOT/'build', ROOT.parent):
            with self.assertRaises(ValueError):
                prepare.prepare(path, 'candidate')
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                prepare.prepare(Path(tmp)/'absent', 'control')

    def test_public_package_fields_are_required_without_fallback(self):
        text = "package: name='com.diraq.ludo.d_iraq_ludo' versionCode='100380' versionName='1.0.0'\nsdkVersion:'23'\ntargetSdkVersion:'36'\nuses-permission: name='android.permission.INTERNET'\n"
        result = verify.package_info(text)
        self.assertEqual(result['versionCode'], 100380)
        self.assertEqual(result['permissions'], ['android.permission.INTERNET'])
        with self.assertRaises(ValueError):
            verify.package_info(text.replace("targetSdkVersion:'36'", ''))

    def test_signing_material_and_private_config_are_excluded_from_artifacts(self):
        for name in ('android/deda-release.jks', 'key.properties', 'private-key.txt',
                     'service-account.json', 'backup.p12', 'secret.pem'):
            self.assertTrue(verify.forbidden_export(name), name)
        for name in ('AndroidManifest.xml', 'lib/arm64-v8a/libapp.so', 'assets/avatar.jpg'):
            self.assertFalse(verify.forbidden_export(name), name)
