import importlib.util
from pathlib import Path
import json
import tarfile
import tempfile
import unittest
import re
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('bound_native_harness', ROOT/'tools/app_stability/native_auth/prepare-harness.py')
native=importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

class NativeAuthBoundaryTest(unittest.TestCase):
    def test_bound_source_stays_in_separate_package_with_pinned_plugins(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);baseline=root/'baseline';harness=root/'harness'
            (baseline/'lib').mkdir(parents=True)
            with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
                for name in ['pubspec.lock','lib/deda_pin_auth.dart']:
                    (baseline/name).write_bytes(archive.extractfile(name).read())
            app=harness/'android/app';(app/'src/main').mkdir(parents=True)
            (harness/'lib').mkdir();(harness/'.metadata').write_text('isolated fixture')
            (app/'build.gradle.kts').write_text('applicationId = "dev.deda.qa.deda_auth_qa"')
            (app/'src/main/AndroidManifest.xml').write_text('<manifest><application/></manifest>')
            native.prepare(harness,baseline)
            manifest=json.loads((harness/'native-pin-source-manifest.json').read_text())
            self.assertEqual(len(manifest['files']),6)
            self.assertEqual((harness/'lib/deda_section_operation_context.dart').read_bytes(),
                             (ROOT/'lib/deda_section_operation_context.dart').read_bytes())
            self.assertEqual(len(manifest['pinnedTransportVersions']),16)
            self.assertIn('DedaAuthRuntime.run', (harness/'lib/deda_pin_auth.dart').read_text())
            self.assertEqual((harness/'lib/deda_auth_session_runtime.dart').read_bytes(),(ROOT/'lib/deda_auth_session_runtime.dart').read_bytes())
            self.assertFalse((app/'google-services.json').exists())
            with self.assertRaisesRegex(ValueError,'overwrite'):native.prepare(harness,baseline)
    def test_workflow_never_exports_source_or_uses_production_credentials_in_native_steps(self):
        source=(ROOT/'.github/workflows/deda-stability-bound-auth-native-qa.yml').read_text()
        for block in source.split('      - name:'):
            if '${{ secrets.' in block:
                self.assertIn('GET ',block);self.assertIn('read_current.py',block)
                self.assertNotIn('run-native.sh',block)
        self.assertIn('--dart-define=DEDA_STABILITY_AUTH_RUNTIME=true',source)
        upload=source[source.index('name: DEDA-BOUND-AUTH-NATIVE-CURRENT-POLICY-NO-APK-NO-SOURCE'):]
        self.assertNotIn('.log',upload);self.assertNotIn('/**',upload)
        script=(ROOT/'tools/app_stability/native_auth/run-native.sh').read_text()
        self.assertNotIn('adb uninstall',script[script.index('adb shell am force-stop'):])
    def test_place_fixtures_cannot_seed_identity_admin_or_wallet_documents(self):
        server=(ROOT/'tools/app_stability/native_auth/policy-server.cjs').read_text()
        writes=re.findall(r"doc\(context\.firestore\(\),'([^']+)','([^']+)'\)",server)
        self.assertEqual(set(writes),{('published_places','native-approved-owner-place'),
            ('published_places','native-duplicate-owner-place')})
        self.assertIn('privilegedIdentitySeeds:false',server)
        self.assertIn('privilegedPublishedPlaceFixtureSeeds:placeFixtureSeeded',server)
        main=(ROOT/'tools/app_stability/native_auth/main.dart').read_text()
        first,second=main.split('Future<void> second(',1)
        self.assertEqual(len(re.findall(r"await record\('([^']+)'",first)),16)
        self.assertEqual(len(re.findall(r"await record\('([^']+)'",second)),4)
