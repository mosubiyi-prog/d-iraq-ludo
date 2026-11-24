import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('home', ROOT/'tools/app_stability/app_package/bind_stage2_home_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class HomeSourceTests(unittest.TestCase):
    def test_protected_home_keeps_two_layouts_all_categories_and_background(self):
        raw = mod.archive_reference()
        a,z = mod.home_span(raw)
        home = raw[a:z]
        self.assertEqual(home.count('const DedaReceivedLocationsPage()'), 2)
        self.assertEqual(home.count('const DedaShareLocationPage()'), 2)
        self.assertEqual(home.count('onPressed: openDedaAssistant'), 2)
        self.assertEqual(home.count("AssetImage('assets/deda_home_bg.jpg')"), 1)
        for marker in ('const OwnerPlacePage()', 'const PersonalPlacesPage()', 'NearbyPlacesPage(category: category)',
                       'DedaPlaceSearchPage(initialQuery: query)', 'Orientation.landscape'):
            self.assertIn(marker, home)
        self.assertIn("label: dedaText('هداياي', 'My gifts')", home)

    def test_exact_callback_rewriter_preserves_nested_routes_and_colors(self):
        src = """Widget tile() {
          return Tile(
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => const Page(),
            )),
            child: InkWell(onTap: () { open(); }, child: Text('test')),
            color: Color(0xFF0B355E),
          );
        }"""
        changed, count = mod.wrap_callbacks(src)
        self.assertEqual(count, 2)
        self.assertEqual(mod.visual_signature(src), mod.visual_signature(changed))
        self.assertIn('onTap: _homeAction(() => Navigator.push', changed)
        self.assertIn('onTap: _homeAction(() { open(); })', changed)
        self.assertEqual(changed.replace('_homeAction(() => Navigator.push(context, MaterialPageRoute<void>(\n              builder: (_) => const Page(),\n            )))', '() => Navigator.push(context, MaterialPageRoute<void>(\n              builder: (_) => const Page(),\n            ))').replace('_homeAction(() { open(); })', '() { open(); }'), src)

    def test_original_reference_visual_check_detects_changes(self):
        raw = mod.archive_reference()
        a,z = mod.home_span(raw)
        home = raw[a:z]
        mod.verify_reference(home, raw)
        with self.assertRaises(ValueError):
            mod.verify_reference(home.replace('Color(0xFF0B355E)', 'Color(0xFF000000)'), raw)

    def test_assistant_corrects_only_obsolete_owner_instruction(self):
        raw = mod.archive_reference()
        a,z = mod.span(raw, mod.ASSISTANT_ENTRY)
        guide = raw[a:z]
        corrected = mod.patch_assistant_guide(guide)
        self.assertIn(mod.ASSISTANT_NEW_AR, corrected)
        self.assertIn(mod.ASSISTANT_NEW_EN, corrected)
        self.assertEqual(corrected.replace(mod.ASSISTANT_NEW_AR, mod.ASSISTANT_OLD_AR)
            .replace(mod.ASSISTANT_NEW_EN, mod.ASSISTANT_OLD_EN), guide)
        self.assertEqual(mod.visual_signature(guide), mod.visual_signature(corrected))

    def test_assistant_rejects_duplicate_or_missing_original_instruction(self):
        raw = mod.archive_reference()
        a,z = mod.span(raw, mod.ASSISTANT_ENTRY)
        guide = raw[a:z]
        for bad in (guide.replace(mod.ASSISTANT_OLD_AR, 'unknown'),
                    guide.replace(mod.ASSISTANT_OLD_EN, mod.ASSISTANT_OLD_EN * 2)):
            with self.assertRaises(ValueError):
                mod.patch_assistant_guide(bad)

    def test_repository_cannot_be_patched(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
