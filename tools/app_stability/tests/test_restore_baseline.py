"""Offline restoration checks. No Flutter, Firebase, Android or network access."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    'restore_baseline', REPO / 'tools/restore_deda_stability_baseline.py')
restore_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore_module)


class RestoreBaselineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_baseline_matches_manifest_and_has_no_platform_files(self):
        output = self.root / 'baseline'
        result = restore_module.restore(output)
        manifest = json.loads((REPO / 'tools/app_stability/100380-baseline-manifest.json').read_text())
        self.assertEqual(result['verifiedFiles'], len(manifest['files']))
        for path, expected in manifest['files'].items():
            self.assertEqual(hashlib.sha256((output / path).read_bytes()).hexdigest(), expected, path)
        self.assertFalse((output / 'android').exists())
        self.assertFalse((output / 'firebase.json').exists())
        self.assertFalse((output / 'lib/deda_stability_read_scope.dart').exists())

    def test_pilot_changes_exactly_two_dart_files(self):
        baseline, pilot = self.root / 'baseline', self.root / 'pilot'
        restore_module.restore(baseline)
        restore_module.restore(pilot, pilot=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(pilot) for p in (pilot / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (pilot / p).read_bytes()}
        self.assertEqual(changed, set(restore_module.PILOT_FILES))
        for name in restore_module.PILOT_FILES:
            self.assertEqual((pilot / name).read_bytes(), (REPO / name).read_bytes())

    def test_measured_restore_changes_only_entry_and_adds_measurement_module(self):
        baseline, measured = self.root / 'baseline', self.root / 'measured'
        restore_module.restore(baseline)
        restore_module.restore(measured, startup_metrics=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(measured) for p in (measured / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (measured / p).read_bytes()}
        self.assertEqual(changed, {'lib/main.dart', restore_module.STARTUP_MODULE})
        original = (baseline / 'lib/main.dart').read_text()
        generated = (measured / 'lib/main.dart').read_text()
        header = 'Future<void> main() async {\n'
        start = original.index(header) + len(header)
        end = original.index('\n}\n\nclass _DedaCleanPageTransitionsBuilder', start)
        # Disabled measurement path retains the exact original body, with only
        # the extra branch indentation. It cannot reorder initialization.
        import textwrap
        self.assertIn(textwrap.indent(original[start:end], '  ') + '\n    return;', generated)
        self.assertIn('if (!dedaStabilityStartupMetricsEnabled)', generated)
        self.assertEqual(generated.count('await runDedaMeasuredStartup('), 1)

    def test_combined_restore_retains_identity_and_startup_overlays(self):
        output = self.root / 'combined'
        restore_module.restore(output, pilot=True, startup_metrics=True)
        for name in (*restore_module.PILOT_FILES, restore_module.STARTUP_MODULE):
            self.assertEqual((output / name).read_bytes(), (REPO / name).read_bytes())
        self.assertIn('runDedaMeasuredStartup', (output / 'lib/main.dart').read_text())
        self.assertFalse((output / 'android').exists())

    def test_instrumentation_rejects_source_drift(self):
        with self.assertRaisesRegex(ValueError, 'exact baseline main'):
            restore_module.instrument_startup('Future<void> main() async {}')

    def test_instrumentation_rejects_a_second_application(self):
        output = self.root / 'measured'
        restore_module.restore(output, startup_metrics=True)
        with self.assertRaisesRegex(ValueError, 'exact baseline main'):
            restore_module.instrument_startup((output / 'lib/main.dart').read_text())

    def test_session_foundation_adds_only_its_module_without_auth_callsite_changes(self):
        baseline, session = self.root / 'baseline', self.root / 'session'
        restore_module.restore(baseline)
        restore_module.restore(session, session_gate=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(session) for p in (session / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (session / p).read_bytes()}
        self.assertEqual(changed, {restore_module.SESSION_MODULE})
        for name in ['lib/main.dart','lib/deda_backend.dart','lib/deda_pin_auth.dart']:
            self.assertNotIn('deda_session_transition_gate', (session / name).read_text())

    def test_all_overlays_preserve_real_auth_implementations(self):
        output = self.root / 'all'
        restore_module.restore(output, pilot=True, startup_metrics=True, session_gate=True)
        manifest = json.loads((REPO / 'tools/app_stability/100380-baseline-manifest.json').read_text())
        for name in ['lib/deda_backend.dart','lib/deda_pin_auth.dart']:
            self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), manifest['files'][name])
        self.assertEqual((output / restore_module.SESSION_MODULE).read_bytes(),
                         (REPO / restore_module.SESSION_MODULE).read_bytes())

    def test_session_flow_adds_two_unwired_modules_without_changing_real_auth(self):
        baseline, flow = self.root / 'baseline', self.root / 'flow'
        restore_module.restore(baseline)
        restore_module.restore(flow, session_flow=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(flow) for p in (flow / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (flow / p).read_bytes()}
        self.assertEqual(changed, {restore_module.SESSION_MODULE, restore_module.SESSION_FLOW_MODULE})
        for name in ['lib/main.dart','lib/deda_backend.dart','lib/deda_pin_auth.dart']:
            self.assertEqual((flow / name).read_bytes(), (baseline / name).read_bytes())
        for module in [restore_module.SESSION_MODULE, restore_module.SESSION_FLOW_MODULE]:
            self.assertEqual((flow / module).read_bytes(), (REPO / module).read_bytes())
        self.assertFalse((flow / 'android').exists())

    def test_owner_adapter_is_unwired_and_keeps_existing_auth_bytes(self):
        baseline, owner = self.root / 'baseline', self.root / 'owner'
        restore_module.restore(baseline)
        restore_module.restore(owner, owner_firebase_port=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(owner) for p in (owner / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (owner / p).read_bytes()}
        self.assertEqual(changed, {restore_module.SESSION_MODULE,
            restore_module.SESSION_FLOW_MODULE, *restore_module.OWNER_PORT_MODULES})
        for name in ['lib/main.dart','lib/deda_backend.dart','lib/deda_pin_auth.dart']:
            self.assertEqual((owner / name).read_bytes(), (baseline / name).read_bytes())
        self.assertFalse((owner / 'android').exists())

    def test_admin_adapter_preserves_entry_visibility_and_real_auth_sources(self):
        baseline, admin = self.root / 'baseline', self.root / 'admin'
        restore_module.restore(baseline)
        restore_module.restore(admin, admin_firebase_adapter=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(admin) for p in (admin / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (admin / p).read_bytes()}
        self.assertEqual(changed, {restore_module.SESSION_MODULE,
            restore_module.SESSION_FLOW_MODULE, *restore_module.OWNER_PORT_MODULES,
            restore_module.ADMIN_ADAPTER_MODULE})
        for name in ['lib/main.dart','lib/deda_backend.dart','lib/deda_pin_auth.dart']:
            self.assertEqual((admin / name).read_bytes(), (baseline / name).read_bytes())
        self.assertFalse((admin / 'android').exists())

    def test_legacy_progress_capture_adds_one_module_without_touching_any_original_source(self):
        baseline, progress = self.root / 'baseline', self.root / 'progress'
        restore_module.restore(baseline)
        restore_module.restore(progress, legacy_progress_capture=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(progress) for p in (progress / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (progress / p).read_bytes()}
        self.assertEqual(changed, {restore_module.LEGACY_PROGRESS_MODULE})
        self.assertFalse((progress / 'android').exists())

    def test_progress_evidence_store_is_unwired_and_has_no_live_rules_or_platform_config(self):
        baseline, archive = self.root / 'baseline', self.root / 'archive'
        restore_module.restore(baseline)
        restore_module.restore(archive, progress_evidence_store=True)
        paths = {p.relative_to(baseline) for p in (baseline / 'lib').rglob('*.dart')}
        paths |= {p.relative_to(archive) for p in (archive / 'lib').rglob('*.dart')}
        changed = {p.as_posix() for p in paths if not (baseline / p).exists()
                   or (baseline / p).read_bytes() != (archive / p).read_bytes()}
        self.assertEqual(changed, {restore_module.SESSION_MODULE,
            restore_module.SESSION_FLOW_MODULE, *restore_module.OWNER_PORT_MODULES,
            restore_module.LEGACY_PROGRESS_MODULE, restore_module.PROGRESS_EVIDENCE_MODULE})
        for name in ['android','firebase.json','firestore.rules']:
            self.assertFalse((archive / name).exists())

    def test_refuses_existing_work_without_touching_it(self):
        output = self.root / 'work'
        output.mkdir()
        (output / 'keep.txt').write_text('existing work')
        with self.assertRaisesRegex(ValueError, 'refusing to overwrite'):
            restore_module.restore(output)
        self.assertEqual((output / 'keep.txt').read_text(), 'existing work')
        self.assertEqual(list(output.iterdir()), [output / 'keep.txt'])

    def test_refuses_output_inside_repository(self):
        with self.assertRaisesRegex(ValueError, 'outside the repository'):
            restore_module.restore(REPO / 'do-not-create-this')
        self.assertFalse((REPO / 'do-not-create-this').exists())

    def test_corrupt_archive_rejected_before_any_output_is_created(self):
        # Use a disposable source fixture; never modify the real snapshot.
        fixture = self.root / 'fixture'
        data = fixture / 'tools/app_stability'
        data.mkdir(parents=True)
        shutil.copy2(REPO / 'tools/app_stability/100380-baseline-manifest.json', data)
        (data / '100380-baseline.tar.gz').write_bytes(b'corrupt')
        original_repo = restore_module.REPO
        restore_module.REPO = fixture
        try:
            output = self.root / 'output'
            with self.assertRaisesRegex(ValueError, 'archive hash mismatch'):
                restore_module.restore(output)
            self.assertFalse(output.exists())
        finally:
            restore_module.REPO = original_repo


if __name__ == '__main__':
    unittest.main()
