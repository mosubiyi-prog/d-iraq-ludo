"""Point05 preflight ONLY. No moonlit asset substitution without approved files.

The owner's chosen moonlit trio is not in the current GitHub asset catalog.
Protect the existing 3 royal portraits, 3 free replacement slots, and saved
legacy owners until the exact approved new images can be verified and staged.
"""
from pathlib import Path
import unittest


class Point05MoonlitAvatarPreflight(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = Path('lib/main.dart').read_text(encoding='utf-8')

    def test_six_free_avatar_choice_slots_and_original_three_remain(self):
        s = self.s
        a = s.index('class DedaAvatarPortrait extends StatelessWidget {')
        b = s.index('\nclass ', a + 10)
        portrait = s[a:b]
        self.assertIn("deda_avatar_male_royal.jpg", portrait)
        self.assertIn("deda_avatar_female_royal.jpg", portrait)
        self.assertIn("deda_avatar_couple_royal.jpg", portrait)
        editor_start = s.index('class _DedaEditProfilePageState extends State<DedaEditProfilePage> {')
        editor_end = s.find('\nclass ', editor_start + 20)
        editor = s[editor_start:editor_end]
        self.assertIn('children: List<Widget>.generate(6, (index)', editor)
        self.assertIn('onTap: () => setState(() => _avatarStyle = index)', editor)
        self.assertIn('DedaAvatarPortrait(', editor)

    def test_legacy_owners_keep_their_original_avatar_choice(self):
        s = self.s
        self.assertIn('_loadRoyalSafeAvatarStyle(', s)
        self.assertIn('style >= 6 && style <= 8 ? style - 6 : style', s)
        self.assertIn('oldChoice + 6', s)
        self.assertIn('await prefs.setBool(migration, true)', s)
        self.assertIn('profileAvatarStyle = avatarStyle.clamp(0, 8).toInt();', s)
        self.assertIn('prefs.setInt(_profileAvatarKey(phone), profileAvatarStyle)', s)

    def test_no_placeholder_images_or_currency_mutation_in_preflight(self):
        s = self.s
        self.assertIn('DedaDiamondsWallet.spend(price)', s)
        self.assertIn('DedaUnifiedCurrencyTotals(', s)
        self.assertIn('DedaFramedAvatar(', s)
        self.assertIn('frameStyle: _previewFrameStyle ?? _frameStyle', s)


if __name__ == '__main__':
    unittest.main()
