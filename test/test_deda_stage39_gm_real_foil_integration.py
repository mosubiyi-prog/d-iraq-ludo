"""Stage39 checks actual admin source receives the ORIGINAL original foil renderer."""
import unittest
from pathlib import Path
from tools.stage_deda_100360_real_admin_foils_on_reconstructed_source import (
    apply, IMPORT, STAMP
)

MAIN_ART = (
    "enum DedaPremiumIdCardColor { gold, diamond, royal, pink }\n"
    "class DedaPremiumIdCard extends StatelessWidget {\n"
    "  const DedaPremiumIdCard({super.key});\n"
    "}\n"
)
ADMIN = Path("lib/deda_exclusive_ids_admin_page.dart")

class ManagerArtContract(unittest.TestCase):
    def test_actual_manager_preview_is_original_card_widget(self):
        old = ADMIN.read_text(encoding="utf-8")
        self.assertNotIn(STAMP, old)
        result = apply(old, MAIN_ART)
        self.assertIn(IMPORT, result)
        self.assertIn(STAMP, result)
        self.assertEqual(result.count("DedaPremiumIdCard("), 1)
        self.assertEqual(result.count("DedaPremiumIdCardColor."), 4)
        self.assertIn("height: 50,", result)
        self.assertEqual(apply(result, MAIN_ART), result)
        self.assertIn("Future<void> _commit", result)

    def test_original_renderer_is_mandatory_not_fake_border(self):
        old = ADMIN.read_text(encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "full premium artwork"):
            apply(old, "class DedaPremiumIdCard extends StatelessWidget {}")
        self.assertNotIn(STAMP, old)

if __name__ == "__main__":
    unittest.main()
