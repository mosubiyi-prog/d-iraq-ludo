"""Contract tests for four REAL artwork shop previews, not mock purchases."""
import unittest
from tools.stage_deda_100360_compact_four_real_foils_after_100359 import apply

EXACT_PAGE = """class DedaPoint17ShopCardAction {}
class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {
  Widget _fixedCard(DedaPremiumIdCardColor color) {
    return Padding(
      child: Column(
        children: [
          DedaPremiumIdCard(
            identifier: _shownIdentifier,
            color: color,
            height: 50,
          ),
          Row(
            children: [
              Text(_cardName(color)),
              Flexible(
                child: Text('تصميم البطاقة: 5,000 ماسة'),
              ),
            ],
          ),
          const SizedBox(height: 3),
          DedaPoint17ShopCardAction(
            identifier: widget.identifier,
            color: color,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text('Existing UI is preserved.');
  }
}
class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {}
"""

class StoreCompactTests(unittest.TestCase):
    def test_keep_artwork_price_and_one_use_action(self):
        result = apply(EXACT_PAGE)
        self.assertIn("DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION", result)
        self.assertEqual(result.count("DedaPremiumIdCard("), 1)
        self.assertEqual(result.count("height: 50,"), 1)
        self.assertEqual(result.count("DedaPoint17ShopCardAction("), 1)
        self.assertEqual(result.count("تصميم البطاقة: 5,000 ماسة"), 1)
        self.assertIn("width: 125,", result)
        self.assertEqual(apply(result), result)

    def test_fail_if_original_artwork_missing(self):
        with self.assertRaisesRegex(ValueError, "artwork"):
            apply(EXACT_PAGE.replace("DedaPremiumIdCard(", "Container("))

    def test_fail_if_purchase_action_missing(self):
        with self.assertRaises(ValueError):
            apply(EXACT_PAGE.replace("DedaPoint17ShopCardAction(\n            identifier:",
                                     "BadButton(\n            identifier:"))

if __name__ == "__main__":
    unittest.main()
