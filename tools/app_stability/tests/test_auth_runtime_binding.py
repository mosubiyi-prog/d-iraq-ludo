import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('auth_binding',ROOT/'tools/app_stability/bind_auth_runtime.py')
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)

class AuthBindingTest(unittest.TestCase):
    def test_nested_awaits_generics_null_fallback_and_strings(self):
        source = '''final x = await f<Map<String, int>>((v) async { return await g(v); }) ?? {}; // await ignored()
final text = 'await ignored()'; final ok = !await h();'''
        actual=binding.guard_awaits(source)
        self.assertIn('await DedaAuthRuntime.wait(() => g(v))',actual)
        self.assertIn(')) ?? {};',actual)
        self.assertIn("'await ignored()'",actual)
        self.assertIn('!await DedaAuthRuntime.wait(() => h())',actual)
        self.assertEqual(actual.count('DedaAuthRuntime.wait'),3)
    def test_await_for_and_unbalanced_input_are_rejected(self):
        for source in ['await for(final x in stream) {}','await f(() {']:
            with self.assertRaises(ValueError): binding.guard_awaits(source)
    def test_generated_overlay_is_atomic_on_any_source_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)
            with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
                for name in ['lib/deda_pin_auth.dart','lib/deda_backend.dart','lib/main.dart','lib/admin_pages.dart']:
                    p=output/name;p.parent.mkdir(exist_ok=True);p.write_bytes(archive.extractfile(name).read())
            original=(output/'lib/deda_pin_auth.dart').read_bytes()
            (output/'lib/admin_pages.dart').write_text('drift')
            with self.assertRaisesRegex(ValueError,'exact baseline'): binding.bind(output)
            self.assertEqual((output/'lib/deda_pin_auth.dart').read_bytes(),original)
    def test_original_auth_paths_and_ui_chains_are_bound_from_exact_source(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)
            with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
                for name in ['lib/deda_pin_auth.dart','lib/deda_backend.dart','lib/main.dart','lib/admin_pages.dart']:
                    p=output/name;p.parent.mkdir(exist_ok=True);p.write_bytes(archive.extractfile(name).read())
            result=binding.bind(output)
            self.assertEqual(len(result),4)
            backend=(output/'lib/deda_backend.dart').read_text()
            pin=(output/'lib/deda_pin_auth.dart').read_text()
            admin=(output/'lib/admin_pages.dart').read_text()
            self.assertNotIn('await auth.signOut()',backend+pin)
            self.assertNotIn('await FirebaseAuth.instance.signOut()',backend)
            self.assertNotIn('await user.delete()',backend)
            self.assertIn('passwordIdentity',admin)
            self.assertIn('DedaAuthRuntime.forSnapshot<void>',admin)
            self.assertIn('DedaAuthRuntime.run<Map<String, dynamic>?>',admin)
            self.assertIn('DedaAuthRuntime.enabled ? DedaAuthRuntime.anonymous',pin)
            main=(output/'lib/main.dart').read_text()
            self.assertEqual(main.count('final logoutIntent = DedaPersonalLogoutIntent();'),2)
            self.assertEqual(main.count('await logoutIntent.commit(isCurrent: () => mounted);'),2)
            self.assertEqual(main.count('if (DedaAuthRuntime.enabled) ++_authAccountEpoch;'),3)
            self.assertIn('_epoch != DedaPreferences._authAccountEpoch',main)
            self.assertIn('DedaPublishedPlaceRecovery(DedaFirebasePlaceRecoveryIo()).recover',backend)
            self.assertIn('expectedAccountKey: recoveryAccountKey',main)
            self.assertIn('prefs.setString(recoveryPlaceKey, recoveredId)',main)
            self.assertIn('recoveryAccountEpoch == DedaPreferences._authAccountEpoch',main)
            with self.assertRaisesRegex(ValueError,'exact baseline'): binding.bind(output)
