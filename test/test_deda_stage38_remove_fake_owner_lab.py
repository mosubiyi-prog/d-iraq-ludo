"""Ensure final store cannot reach mocked 25k diamond or fake GM grant flow."""
import unittest
from tools.stage_deda_100360_remove_fake_store_sandbox import apply
from tools.stage_deda_100359_owner_private_sandbox_after_point17_2026_10_19 import (
    ADDITION, IMPORT,
)

BASE = """class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {
  Widget _fixedCard(DedaPremiumIdCardColor color) {
    return DedaPoint17ShopCardAction(
      identifier: widget.identifier,
      color: color,
    );
  }
  Widget build(BuildContext context) {
    return Column(children: [
              const SizedBox(height: 7),
              Expanded(child: Text('real purchase')),
    ]);
  }
}
class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {}
"""
def old_lab():
    needle = "              const SizedBox(height: 7),\n              Expanded("
    if BASE.count(needle) != 1:
        raise AssertionError("synthetic fixture invalid")
    return IMPORT + BASE.replace(needle, ADDITION)

class FakeLabRemovalTests(unittest.TestCase):
    def test_reverts_only_old_mock_launcher_and_import(self):
        before = old_lab()
        after = apply(before)
        self.assertEqual(after, BASE)
        self.assertEqual(apply(after), BASE)
        self.assertIn("DedaPoint17ShopCardAction(", after)
        self.assertNotIn("DedaOwnerQaSandboxPage()", after)

    def test_partial_mock_is_blocked_not_silently_erased(self):
        with self.assertRaisesRegex(ValueError, "unexpected"):
            apply(old_lab().replace(IMPORT, ""))

    def test_real_card_markup_unchanged(self):
        source = old_lab()
        after = apply(source)
        self.assertIn("Expanded(child: Text('real purchase'))", after)
        self.assertNotIn("مختبر تجربة الشراء والمنح", after)

if __name__ == "__main__":
    unittest.main()
