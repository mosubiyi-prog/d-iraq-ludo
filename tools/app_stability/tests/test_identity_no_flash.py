"""Regression guard: no canonical-ID flash while premium ID is resolving."""
import importlib.util
import tarfile
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
BINDER = REPO / 'tools/app_stability/bind_active_id_no_flash.py'
ARCHIVE = REPO / 'tools/app_stability/100380-baseline.tar.gz'
SOURCES = (
    'lib/deda_six_active_identity.dart',
    'lib/deda_qa32_active_account_scope.dart',
)


class IdentityNoFlashTests(unittest.TestCase):
    def _restore_two_sources(self, root):
        with tarfile.open(ARCHIVE, 'r:gz') as tar:
            for name in SOURCES:
                member = tar.getmember(name)
                content = tar.extractfile(member).read()
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)

    def test_verified_identifier_never_uses_old_id_while_loading(self):
        spec = importlib.util.spec_from_file_location('identity_no_flash', BINDER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as t:
            root = Path(t)
            self._restore_two_sources(root)
            before = {name: (root / name).read_text() for name in SOURCES}
            module.bind(root)
            owner = (root / SOURCES[0]).read_text()
            scope = (root / SOURCES[1]).read_text()
            self.assertIn('deda-active-id-awaiting-verification', owner)
            self.assertIn('proof?.displayId ??', owner)
            self.assertIn('DedaStage71OwnedIdentifierService.enabled ? null : originalId', owner)
            self.assertNotIn('final id = proof?.displayId ?? originalId;', owner)
            self.assertIn('return const SizedBox.shrink(); // No unverified sender ID flash.', owner)
            self.assertIn('if (!snapshot.hasData ||', owner)
            self.assertIn('!_proof!.verifiedFor(uid, original)', scope)
            self.assertIn('  void _refresh() {\n    // Active-ID selection changed', scope)
            self.assertIn('    _invalidateProof();\n    _load();', scope)
            self.assertNotIn('if (_proof != null) setState(() => _proof = null);', scope)
            self.assertEqual(before[SOURCES[0]].count('class DedaSixIdentityCopy'),
                             owner.count('class DedaSixIdentityCopy'))
            # Same source cannot be patched twice; any drift must fail closed.
            with self.assertRaises(ValueError):
                module.bind(root)

    def test_binder_changes_no_backend_or_wallet(self):
        source = BINDER.read_text()
        self.assertNotIn('firestore.rules', source)
        self.assertNotIn('functions/index.js', source)
        self.assertNotIn('spendCoins', source)
        self.assertNotIn('claimTaskReward', source)


if __name__ == '__main__':
    unittest.main()
