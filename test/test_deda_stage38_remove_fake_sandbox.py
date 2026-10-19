"""QA fake-grant page must never ship in the owner completed store."""
import unittest
from tools.stage_deda_100360_remove_fake_store_sandbox import apply, MARKER
from tools.stage_deda_100359_owner_private_sandbox_after_point17_2026_10_19 import (
    ADDITION, ANCHOR, IMPORT,
)
BEFORE = (IMPORT +
    "class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {\n" +
    "  Widget card() => DedaPoint17ShopCardAction(identifier: widget.identifier);\n" +
    "  Widget shop() => Column(children: [\n" +
    ADDITION + "\n  ]);\n}\n" +
    "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {}\n")

class FakeSandboxRemoval(unittest.TestCase):
    def test_mock_25k_wallet_and_grants_are_not_reachable(self):
        result = apply(BEFORE)
        self.assertNotIn(MARKER, result)
        self.assertNotIn("DEDA_OWNER_PRIVATE_SANDBOX", result)
        self.assertNotIn("DedaOwnerQaSandboxPage", result)
        self.assertNotIn(IMPORT, result)
        self.assertIn("DedaPoint17ShopCardAction", result)
        self.assertIn(ANCHOR, result)
        self.assertEqual(apply(result), result)

    def test_refuse_partial_script_without_import(self):
        with self.assertRaisesRegex(ValueError, "unexpected"):
            apply(BEFORE.replace(IMPORT, ""))

    def test_refuse_missing_real_shop_action(self):
        with self.assertRaisesRegex(ValueError, "structure"):
            apply(BEFORE.replace("DedaPoint17ShopCardAction", "FakeCard"))

if __name__ == "__main__":
    unittest.main()
