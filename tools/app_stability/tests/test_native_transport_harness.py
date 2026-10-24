"""Guard the disposable harness boundary, offline; no Android or SDK launch."""
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('native_harness', ROOT / 'tools/app_stability/native_transport/prepare-harness.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeHarnessBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.harness = self.root / 'deda-native-transport-qa'
        self.baseline = self.root / 'baseline'
        self.baseline.mkdir()
        with tarfile.open(ROOT / 'tools/app_stability/100380-baseline.tar.gz') as archive:
            (self.baseline / 'pubspec.lock').write_bytes(archive.extractfile('pubspec.lock').read())
        app = self.harness / 'android/app'
        (app / 'src/main').mkdir(parents=True)
        (self.harness / '.metadata').write_text('disposable fixture')
        (self.harness / 'lib').mkdir()
        (app / 'build.gradle.kts').write_text('applicationId = "dev.deda.qa.deda_transport_qa"')
        (app / 'src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application/></manifest>')

    def tearDown(self):
        self.temp.cleanup()

    def test_only_exact_transport_modules_and_demo_main_are_copied(self):
        native.prepare(self.harness, self.baseline)
        files = {p.name for p in (self.harness / 'lib').iterdir()}
        self.assertEqual(files, {*native.MODULES, 'main.dart'})
        manifest = json.loads((self.harness / 'native-source-manifest.json').read_text())
        self.assertEqual(manifest['projectId'], 'demo-deda-progress-archive')
        self.assertFalse((self.harness / 'android/app/google-services.json').exists())
        self.assertIn('usesCleartextTraffic="true"', (self.harness / 'android/app/src/main/AndroidManifest.xml').read_text())

    def test_repository_output_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            native.prepare(ROOT, self.baseline)

    def test_missing_flutter_marker_refused_without_creating_output(self):
        target = self.root / 'absent'
        with self.assertRaisesRegex(ValueError, 'flutter-create'):
            native.prepare(target, self.baseline)
        self.assertFalse(target.exists())

    def test_actual_deda_package_or_firebase_config_is_refused(self):
        gradle = self.harness / 'android/app/build.gradle.kts'
        gradle.write_text('applicationId = "com.diraq.ludo.d_iraq_ludo"')
        with self.assertRaisesRegex(ValueError, 'isolated QA application ID'):
            native.prepare(self.harness, self.baseline)
        gradle.write_text('applicationId = "dev.deda.qa.deda_transport_qa"')
        (self.harness / 'android/app/google-services.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'without Firebase config'):
            native.prepare(self.harness, self.baseline)

    def test_second_preparation_cannot_overwrite_existing_work(self):
        native.prepare(self.harness, self.baseline)
        source = self.harness / 'lib/main.dart'
        source.write_text('keep existing work')
        with self.assertRaisesRegex(ValueError, 'refusing to overwrite'):
            native.prepare(self.harness, self.baseline)
        self.assertEqual(source.read_text(), 'keep existing work')

    def test_transports_version_drift_is_refused(self):
        native.prepare(self.harness, self.baseline)
        lock = self.baseline / 'pubspec.lock'
        (self.harness / 'pubspec.lock').write_text(lock.read_text())
        native.verify(self.harness, self.baseline)
        altered = lock.read_text().replace('version: "5.6.12"', 'version: "99.0.0"')
        (self.harness / 'pubspec.lock').write_text(altered)
        with self.assertRaisesRegex(ValueError, 'drifted'):
            native.verify(self.harness, self.baseline)

    def test_runtime_is_exact_module_and_pilot_enabled_only_for_disposable_debug_build(self):
        self.assertIn('deda_progress_backup_runtime.dart', native.MODULES)
        workflow=(ROOT / '.github/workflows/deda-stability-native-transport-qa.yml').read_text()
        self.assertIn('flutter build apk --debug --dart-define=DEDA_STABILITY_PROGRESS_BACKUP_PILOT=true', workflow)
        script=(ROOT / 'tools/app_stability/native_transport/run-native.sh').read_text()
        self.assertIn('KEYCODE_HOME', script)
        self.assertIn('background-ready --timeout', script)
        self.assertIn('backgrounded --timeout', script)
        self.assertIn('test "$background_pid" = "$first_pid"', script)
        self.assertIn('adb shell am force-stop "$pkg"', script)

    def test_demo_config_keeps_rules_inside_its_project_root(self):
        config = json.loads((ROOT / 'tools/app_stability/native_transport/firebase.json').read_text())
        self.assertEqual(config['firestore']['rules'], 'firestore.rules')
        for service in ['auth', 'firestore']:
            self.assertEqual(config['emulators'][service]['host'], '127.0.0.1')
