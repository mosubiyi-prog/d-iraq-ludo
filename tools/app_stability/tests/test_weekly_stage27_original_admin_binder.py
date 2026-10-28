"""Stage27 integration-contract tests against SHA-verified ORIGINAL admin source.

Reads the immutable 100380 archive, never replaces it; tests only a temporary
fake candidate workspace and exercises actual Stage27 patch+fail-closed rules.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
MANIFEST = REPO / 'tools/app_stability/100380-baseline-manifest.json'
ARCHIVE = REPO / 'tools/app_stability/100380-baseline.tar.gz'
BINDER = REPO / 'tools/app_stability/app_package/bind_weekly_admin_league_stage27.py'
PROTECTED = [
    'lib/admin_pages.dart',
    'lib/main.dart',
    'lib/deda_backend.dart',
    'lib/deda_social_service.dart',
    'lib/traffic_quiz_page.dart',
    'pubspec.yaml',
    'pubspec.lock',
]


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def original_sources():
    manifest = json.loads(MANIFEST.read_text())
    assert sha(ARCHIVE.read_bytes()) == manifest['archiveSHA256']
    with tarfile.open(ARCHIVE, mode='r:gz') as tar:
        blobs = {p: tar.extractfile(p).read() for p in PROTECTED}
    for path, blob in blobs.items():
        assert sha(blob) == manifest['files'][path], path
    return blobs


def binder():
    spec = importlib.util.spec_from_file_location('stage27_original_binder', BINDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Stage27OriginalAdminBinderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='deda_stage27_verified_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.blobs = original_sources()
        # Emulate the Stage13/22 source-only leaderboard files which the
        # verified 100394 bind chain introduces after the 100380 archive.
        for path in (
            'lib/deda_weekly_leaderboard_page.dart',
            'lib/deda_weekly_snapshot_decode.dart',
        ):
            self.blobs[path] = (REPO / path).read_bytes()
        for rel, blob in self.blobs.items():
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(blob)
        self.metadata = {
            'package': 'com.diraq.ludo.d_iraq_ludo',
            'versionCode': 100394,
            'variant': 'candidate',
            'financialRestoreEnabled': False,
            'completeOwnerDelivery': False,
            'productionExecutionPerformed': False,
            'weeklyStage18': {'writesRealWallet': False, 'writesRealXp': False,
                              'writesFirestore': False},
            'weeklyStage19': {'walletOrXpModified': False},
            'sourceHashes': {p: sha(b) for p, b in self.blobs.items()},
        }
        self._write_meta()

    def _write_meta(self):
        (self.root / 'internal-build-inputs.json').write_text(json.dumps(self.metadata))

    def test_real_immutable_dashboard_is_patched_once_and_preserves_protected(self):
        result = binder().bind(self.root)
        self.assertTrue(result['adminLeagueTileInOriginal'])
        self.assertTrue(result['adminGeneralManagerOnly'])
        self.assertFalse(result['liveLeagueControlsEnabled'])
        self.assertFalse(result['writesFirestore'])
        original = self.blobs['lib/admin_pages.dart'].decode()
        modified = (self.root / 'lib/admin_pages.dart').read_text()
        self.assertEqual(modified.count("Key('deda_admin_league_dashboard_tile')"), 1)
        self.assertIn("DedaAdminLeaguePage(isArabic: ar)", modified)
        for dependency in (
            'lib/deda_weekly_competitor_public_card.dart',
            'lib/deda_weekly_leaderboard_tap_surface.dart',
        ):
            self.assertEqual((self.root / dependency).read_bytes(),
                             (REPO / dependency).read_bytes())
        self.assertIn("normalizeAdminStatus(profile) == 'active'", modified)
        self.assertIn("accentColor: const Color(0xFF133F65)", modified)
        self.assertIn("if (DedaBackend.adminHasPermission(\n                          profile, 'supportRead'))", modified)
        self.assertEqual(
            modified.count("if (DedaBackend.adminHasPermission(\n                          profile, 'supportRead'))"),
            original.count("if (DedaBackend.adminHasPermission(\n                          profile, 'supportRead'))"))
        for p, blob in self.blobs.items():
            if p != 'lib/admin_pages.dart':
                self.assertEqual((self.root / p).read_bytes(), blob, p)
        data = json.loads((self.root / 'internal-build-inputs.json').read_text())
        self.assertEqual(data['versionCode'], 100395)
        self.assertFalse(data['completeOwnerDelivery'])
        self.assertFalse(data['financialRestoreEnabled'])
        with self.assertRaises(ValueError):
            binder().bind(self.root)

    def test_mutated_admin_input_is_blocked_before_any_partial_output(self):
        p = self.root / 'lib/admin_pages.dart'
        p.write_text(p.read_text().replace("profile, 'supportRead'",
                                           "profile, 'supportDANGEROUS'"))
        with self.assertRaisesRegex(ValueError, 'source bind drift'):
            binder().bind(self.root)
        self.assertFalse((self.root / 'lib/deda_admin_league_page.dart').exists())

    def test_unverified_financial_state_refused(self):
        self.metadata['financialRestoreEnabled'] = True
        self._write_meta()
        with self.assertRaisesRegex(ValueError, 'Unverified prior original'):
            binder().bind(self.root)
        self.assertFalse((self.root / 'lib/deda_admin_league_page.dart').exists())


if __name__ == '__main__':
    unittest.main()
