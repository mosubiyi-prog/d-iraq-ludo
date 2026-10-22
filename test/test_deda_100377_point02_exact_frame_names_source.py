"""Real reconstructed source guard: frame display titles come from 16 catalog entries."""
from pathlib import Path
import re
import unittest


class Point02FrameNameSourceTest(unittest.TestCase):
    def test_13_paid_names_are_unique_real_catalog_titles(self):
        text = Path('lib/deda_lab_verified_frame_catalog.dart').read_text(encoding='utf-8')
        rows = re.findall(
            r"DedaLabFrameSpec\\(id:'(FRAME_\\d+)',nameAr:'([^']+)'"
            r".*?priceDiamonds:(\\d+),", text, re.S)
        self.assertEqual(16, len(rows))
        paid = [(id_, name) for id_, name, price in rows if price == '1000']
        free = [(id_, name) for id_, name, price in rows if price == '0']
        self.assertEqual(13, len(paid))
        self.assertEqual(3, len(free))
        self.assertEqual(13, len({name for _, name in paid}))
        self.assertEqual(13, len({id_ for id_, _ in paid}))
        self.assertNotIn('وردي ملكي', {name for _, name in paid})

    def test_reconstructed_store_label_uses_canonical_paid_catalog(self):
        main = Path('lib/main.dart').read_text(encoding='utf-8')
        anchor = '// DEDA_100377_POINT02_EXACT_LAB_PAID_FRAME_NAMES'
        self.assertEqual(1, main.count(anchor))
        index = main.index(anchor)
        label = main[index:index+850]
        self.assertIn('index >= 6', label)
        self.assertIn('DedaLabPremiumFrameStyles.byProfileStyle(index)!.nameAr', label)
        self.assertIn('maxLines: 3', label)
        self.assertIn("dedaText('زمردي ملكي'", label)
        self.assertIn("dedaText('ذهبي ملكي'", label)
        self.assertIn("dedaText('وردي ملكي'", label)
        self.assertEqual(1, main.count('DEDA_100377_POINT01_LAB_FRAME_CHECKOUT_GUARDED'))
        self.assertIn('children: List<Widget>.generate(16, (offset)', main)


if __name__ == '__main__':
    unittest.main()
