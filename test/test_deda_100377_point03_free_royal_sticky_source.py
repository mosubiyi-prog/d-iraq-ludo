"""Point03: the three FREE royal frames retain the owner's pinned preview and saved appearance."""
from pathlib import Path
import re
import unittest


class Point03RoyalFreeFrameTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = Path('lib/main.dart').read_text(encoding='utf-8')

    def test_all_six_legacy_and_royal_slots_free_with_paid_guard(self):
        self.assertIn('bool dedaProfileFrameIsFree(int style) => style >= 0 && style < 6;', self.src)
        self.assertIn('final free = dedaProfileFrameIsFree(index);', self.src)
        self.assertIn('onTap: free', self.src)
        self.assertIn('final index = offset + 3;', self.src)
        self.assertIn('children: List<Widget>.generate(16, (offset)', self.src)

    def test_preview_is_fixed_above_scrollable_choices_and_savable(self):
        anchor = 'class _DedaEditProfilePageState extends State<DedaEditProfilePage> {'
        a = self.src.index(anchor)
        b = self.src.find('\nclass ', a + len(anchor))
        editor = self.src[a:b]
        pinned = editor.index('frameStyle: _previewFrameStyle ?? _frameStyle')
        scroll = editor.index("key: const Key('deda_edit_profile_scroll_choices')")
        self.assertLess(pinned, scroll)
        self.assertIn('await DedaPreferences.setProfileAppearance(', editor)
        self.assertIn('frameStyle: _frameStyle,', editor)
        self.assertIn('_frameStyle = index;', editor)
        self.assertIn('onTap: free', editor)
        self.assertIn('frameStyle: _previewFrameStyle ?? _frameStyle', editor)
        self.assertIn('profileFrameStyle=frameStyle.clamp(0,18).toInt();', re.sub(r'\s+', '', self.src))
        self.assertIn('prefs.setInt(_profileFrameKey(phone),profileFrameStyle)', re.sub(r'\s+', '', self.src))

    def test_public_friend_card_renders_owners_saved_frame(self):
        a = self.src.index('class DedaFriendPublicProfilePage extends StatelessWidget {')
        b = self.src.find('\nclass ', a + len('class DedaFriendPublicProfilePage'))
        public = self.src[a:b]
        self.assertIn('DedaFramedAvatar(', public)
        self.assertIn('frameStyle: profile.frameStyle', public)
        self.assertIn('avatarStyle: profile.avatarStyle', public)


if __name__ == '__main__':
    unittest.main()
