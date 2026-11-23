"""Stage2 read-only visual regression: protect owner artwork and original colors."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "tools/app_stability/app_package/audit_stage2_profile_visual_parity_2026_11_24.py"
spec = importlib.util.spec_from_file_location("stage2_profile_visual", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def synthetic_grid():
    cards = []
    for title, first, second in mod.PALETTE:
        cards.append(
            "    _featureCard(\n"
            f"      title: dedaText('{title}', 'Label'),\n"
            "      subtitle: dedaText('عنوان ثانوي', 'Subtitle'),\n"
            f"      colors: const <Color>[Color({first}), Color({second})],\n"
            "    ),\n"
        )
    return "  Widget _featureGrid() {\n" + "".join(cards) + (
        "  }\n"
        "  Widget _featureCard(Widget value) {\n"
        "    return Ink(decoration: BoxDecoration(gradient: LinearGradient(" 
        "colors: colors)));\n"
        "  }\n"
    )


class Stage2ProfileVisualPariy(unittest.TestCase):
    def test_all_six_original_gradient_pairs_and_card_order(self):
        self.assertEqual(mod.visual_palette(synthetic_grid()), list(mod.PALETTE))

    def test_reject_changed_card_color_reorder_and_duplicate(self):
        before = synthetic_grid()
        for body in (
            before.replace("0xFF914BE1", "0xFF914BE2"),
            before.replace("0xFF0BB97B", "0xFF0BB970"),
            before.replace("title: dedaText('متجري'", "title: dedaText('الصور'"),
            before.replace("title: dedaText('متجري'", "title: dedaText('تعديل الملف'"),
        ):
            with self.subTest(case=body[:115]), self.assertRaises(ValueError):
                mod.visual_palette(body)

    def test_subtitles_cannot_be_mistaken_for_original_card(self):
        original = synthetic_grid()
        self.assertEqual(len(mod.visual_palette(original)), 6)
        bad = original.replace("subtitle: dedaText('عنوان ثانوي', 'Subtitle'),",
                               "subtitle: dedaText('الشارات', 'Subtitle'),", 1)
        self.assertEqual(len(mod.visual_palette(bad)), 6)

    def test_approved_six_portraits_and_existing_royal_backgrounds_are_present(self):
        manifest = json.loads((ROOT/"docs/DEDA_OWNER18_APPROVED_AVATARS_2026-10-23.json")
                              .read_text(encoding="utf-8"))
        approved = mod.approved_art(ROOT, manifest)
        self.assertEqual(len(approved), 3)
        self.assertEqual(set(manifest["inner_display"]), {111})
        for asset in (*mod.ROYAL_ASSETS, *mod.ROYAL_FRAMES, *mod.ROYAL_BACKGROUNDS):
            self.assertTrue((ROOT / asset).is_file(), asset)

    def test_reject_unverified_avatar_slot_or_approval(self):
        manifest = json.loads((ROOT/"docs/DEDA_OWNER18_APPROVED_AVATARS_2026-10-23.json")
                              .read_text(encoding="utf-8"))
        changed = json.loads(json.dumps(manifest))
        changed["owner_approved_exact_artwork"] = False
        with self.assertRaises(ValueError):
            mod.approved_art(ROOT, changed)
        changed = json.loads(json.dumps(manifest))
        changed["avatars"][1]["slot"] = 5
        with self.assertRaises(ValueError):
            mod.approved_art(ROOT, changed)
        changed = json.loads(json.dumps(manifest))
        changed["avatars"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            mod.approved_art(ROOT, changed)


if __name__ == "__main__":
    unittest.main()
