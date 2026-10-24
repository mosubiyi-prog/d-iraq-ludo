"""Offline original-source, privacy and no-seed native harness boundaries."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('native_pin_harness', ROOT / 'tools/app_stability/native_pin/prepare-harness.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class OriginalNativePinBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.baseline = self.root / 'baseline'
        (self.baseline / 'lib').mkdir(parents=True)
        with tarfile.open(ROOT / 'tools/app_stability/100380-baseline.tar.gz') as archive:
            for name in ['pubspec.lock', 'lib/deda_pin_auth.dart']:
                (self.baseline / name).write_bytes(archive.extractfile(name).read())
        self.harness = self.root / 'harness'
        app = self.harness / 'android/app'
        (app / 'src/main').mkdir(parents=True)
        (self.harness / 'lib').mkdir()
        (self.harness / '.metadata').write_text('disposable flutter fixture')
        (app / 'build.gradle.kts').write_text('applicationId = "dev.deda.qa.deda_pin_qa"')
        (app / 'src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application/></manifest>')

    def tearDown(self):
        self.temporary.cleanup()

    def test_original_pin_and_real_modules_are_copied_exactly_without_configuration(self):
        native.prepare(self.harness, self.baseline)
        manifest = json.loads((self.harness / 'native-pin-source-manifest.json').read_text())
        self.assertEqual(len(manifest['files']), 10)
        self.assertEqual(len(manifest['pinnedTransportVersions']), 16)
        self.assertEqual((self.harness / 'lib/deda_pin_auth.dart').read_bytes(),
                         (self.baseline / 'lib/deda_pin_auth.dart').read_bytes())
        self.assertEqual(hashlib.sha256((self.harness / 'lib/deda_pin_auth.dart').read_bytes()).hexdigest(), manifest['originalPinAuthSHA256'])
        self.assertFalse((self.harness / 'android/app/google-services.json').exists())
        self.assertEqual(manifest['projectId'], 'demo-deda-live-progress-compat')

    def test_pin_source_drift_is_rejected_before_mutating_the_harness(self):
        (self.harness / 'pubspec.yaml').write_text('keep original counter')
        (self.baseline / 'lib/deda_pin_auth.dart').write_text('changed source')
        with self.assertRaisesRegex(ValueError, 'source hash'):
            native.prepare(self.harness, self.baseline)
        self.assertEqual((self.harness / 'pubspec.yaml').read_text(), 'keep original counter')
        self.assertEqual(list((self.harness / 'lib').iterdir()), [])

    def test_production_package_configuration_and_repo_outputs_are_rejected(self):
        app = self.harness / 'android/app'
        (app / 'build.gradle.kts').write_text('applicationId = "com.diraq.ludo.d_iraq_ludo"')
        with self.assertRaisesRegex(ValueError, 'isolated package'):
            native.prepare(self.harness, self.baseline)
        (app / 'build.gradle.kts').write_text('applicationId = "dev.deda.qa.deda_pin_qa"')
        (app / 'google-services.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'isolated package'):
            native.prepare(self.harness, self.baseline)
        with self.assertRaisesRegex(ValueError, 'outside repository'):
            native.prepare(ROOT, self.baseline)

    def test_second_preparation_cannot_overwrite_existing_work(self):
        native.prepare(self.harness, self.baseline)
        (self.harness / 'lib/main.dart').write_text('keep work')
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            native.prepare(self.harness, self.baseline)
        self.assertEqual((self.harness / 'lib/main.dart').read_text(), 'keep work')

    def test_native_plugin_drift_is_rejected(self):
        native.prepare(self.harness, self.baseline)
        shutil.copy2(self.baseline / 'pubspec.lock', self.harness / 'pubspec.lock')
        native.transport.verify(self.harness, self.baseline)
        p = self.harness / 'pubspec.lock'
        p.write_text(p.read_text().replace('version: "5.7.0"', 'version: "99.0.0"'))
        with self.assertRaisesRegex(ValueError, 'drifted'):
            native.transport.verify(self.harness, self.baseline)

    def test_rule_loader_protocol_guards_offline_without_sdk_or_network(self):
        result = subprocess.run(['node', '--test', '--test-reporter=tap', str(ROOT / 'tools/app_stability/native_pin/policy-server.test.cjs')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('# pass 5', result.stdout)

    def test_workflow_credentials_are_read_only_steps_and_artifacts_are_explicit_json(self):
        workflow = (ROOT / '.github/workflows/deda-stability-native-pin-current-policy-qa.yml').read_text()
        credential_steps = [block for block in workflow.split('      - name:') if '${{ secrets.' in block]
        self.assertEqual(len(credential_steps), 2)
        for block in credential_steps:
            self.assertIn('GET ', block)
            self.assertIn('read_current.py', block)
            self.assertNotIn('run-native.sh', block)
        upload = workflow[workflow.index('name: DEDA-NATIVE-ORIGINAL-PIN-CURRENT-POLICY-SANITIZED'):]
        self.assertNotIn('.log', upload)
        self.assertNotIn('/**', upload)
        for filename in ['rules-compat-report.json', 'native-pin-result.json', 'native-pin-source-manifest.json', 'pinned-versions.json']:
            self.assertIn('/' + filename, upload)
        server = (ROOT / 'tools/app_stability/native_pin/policy-server.cjs').read_text()
        self.assertNotIn("require('firebase-admin", server)
        self.assertNotIn("req.url==='/seed'", server)
        script = (ROOT / 'tools/app_stability/native_pin/run-native.sh').read_text()
        after_stop = script[script.index('adb shell am force-stop'):]
        self.assertNotIn('adb uninstall', after_stop)
        self.assertNotIn('pm clear', after_stop)
        self.assertIn('test "$first_pid" != "$second_pid"', after_stop)
