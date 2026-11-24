import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('map_foundation', ROOT/'tools/app_stability/app_package/audit_stage2_map_foundation_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class MapFoundationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = mod.home.archive_reference()

    def test_all_five_parts_inventoried_from_protected_archive(self):
        result = mod.verify(self.original, self.original, require_bound=False)
        self.assertEqual(set(result), {'1','2','3','4','5'})
        self.assertIn('DedaMapPlaceMarker', result['2'])
        self.assertIn('DedaRouteService', result['5'])

    def test_provider_cache_and_map_styles_fail_closed(self):
        for before, after in (
            ('https://tile.openstreetmap.org/', 'https://different.invalid/'),
            ('keepBuffer: 4,', 'keepBuffer: 1,'),
            ('  hybrid,\n}', '  hybridRemoved,\n}'),
        ):
            changed = self.original.replace(before, after, 1)
            self.assertNotEqual(changed, self.original)
            with self.assertRaises(ValueError):
                mod.verify(changed, self.original, require_bound=False)

    def test_lost_gesture_and_map_page_are_rejected(self):
        a,z = mod.home.span(self.original, 'class _MapReadyPageState ')
        body = self.original[a:z]
        for before,after in (('InteractiveFlag.all','InteractiveFlag.none'),
                             ('initialZoom: 11.8','initialZoom: 16.0'),
                             ('Geolocator.requestPermission()','otherPermission()')):
            changed = self.original[:a] + body.replace(before, after, 1) + self.original[z:]
            self.assertNotEqual(changed, self.original)
            with self.assertRaises(ValueError):
                mod.verify(changed, self.original, require_bound=False)

    def test_unbound_archive_cannot_be_reported_as_assembled_success(self):
        with self.assertRaises(ValueError):
            mod.verify(self.original, self.original)
        with self.assertRaises(ValueError):
            mod.audit(ROOT)

if __name__ == '__main__':
    unittest.main()
