"""Exact reviewed 100450 admin-exit merge overlap; fail closed on unknowns."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                       "tools/app_stability/app_package"))
from reconcile_stage2_auth_conflicts import reconcile


def fixture(first_guard=True, second_guard=True):
    begin_guard = """    String? confirmedAdminUid;
    if (dedaLinkedOwnerCompatEnabled) {
      final proof = await FirebaseFirestore.instance
          .collection('admins')
          .doc(principal.uid)
          .get(const GetOptions(source: Source.server));
      if (!DedaLinkedOwnerSessionPolicy.maySignOutAdminPrincipal(
        linkedOwnerPilotEnabled: dedaLinkedOwnerCompatEnabled,
      )) {
        throw StateError('admin-logout-refused-preserve-deda-owner');
      }
      confirmedAdminUid = principal.uid;
    }
""" if first_guard else "    // unknown, unreviewed auth edit\n"
    finish_guard = """    if (dedaLinkedOwnerCompatEnabled &&
        FirebaseAuth.instance.currentUser?.uid != confirmedAdminUid) {
      throw StateError('admin-logout-principal-changed-owner-preserved');
    }
    await FirebaseAuth.instance.signOut();
""" if second_guard else "    await FirebaseAuth.instance.signOut();\n"
    return (
        "  static Future<void> signOutAdmin() async {\n"
        "<<<<<<< signed-100436\n"
        "    return DedaAuthRuntime.run<void>(\n"
        "      kind: DedaSessionTransitionKind.logout,\n"
        "      action: () async {\n"
        "||||||| ancestor\n"
        "=======\n"
        + begin_guard +
        ">>>>>>> stage2-100450\n"
        "    _clearAdminProfileCache();\n"
        "<<<<<<< signed-100436\n"
        "    await DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut(FirebaseAuth.instance));\n"
        "      });\n"
        "||||||| ancestor\n"
        "    await FirebaseAuth.instance.signOut();\n"
        "=======\n"
        + finish_guard +
        ">>>>>>> stage2-100450\n"
        "  }\n"
    ).encode()


class AdminExitMerge(unittest.TestCase):
    def test_preserves_both_uid_proof_and_signed_runtime(self):
        merged, count = reconcile("lib/deda_backend.dart", fixture())
        self.assertEqual(count, 2)
        code = merged.decode()
        self.assertNotIn("<<<<<<<", code)
        self.assertNotIn(">>>>>>>", code)
        self.assertIn("maySignOutAdminPrincipal(", code)
        self.assertIn("admin-logout-principal-changed-owner-preserved", code)
        self.assertEqual(code.count("DedaAuthRuntime.run<void>("), 1)
        self.assertEqual(code.count(
            "DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut("
            "FirebaseAuth.instance))"), 1)
        self.assertLess(code.index("maySignOutAdminPrincipal("),
                        code.index("DedaAuthRuntime.signOut("))
        self.assertLess(code.index(
            "admin-logout-principal-changed-owner-preserved"),
            code.index("DedaAuthRuntime.signOut("))

    def test_unknown_owner_proof_conflict_remains_unresolved(self):
        merged, count = reconcile("lib/deda_backend.dart",
                                  fixture(first_guard=False))
        self.assertEqual(count, 1)
        self.assertIn(b"<<<<<<< signed-100436", merged)

    def test_missing_uid_race_guard_cannot_replace_signed_logout(self):
        merged, count = reconcile("lib/deda_backend.dart",
                                  fixture(second_guard=False))
        self.assertEqual(count, 1)
        self.assertIn(b"<<<<<<< signed-100436", merged)

    def test_other_source_file_never_uses_backend_reconciliation(self):
        merged, count = reconcile("lib/main.dart", fixture())
        self.assertEqual(count, 0)
        self.assertIn(b"<<<<<<< signed-100436", merged)


if __name__ == "__main__":
    unittest.main()
