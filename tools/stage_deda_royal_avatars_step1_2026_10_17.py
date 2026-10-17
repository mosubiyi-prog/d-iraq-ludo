#!/usr/bin/env python3
"""DEDA 2026-10-17: conservative first-batch of 3 royal profile avatars.

Apply ONLY to the fully reconstructed 100340 source with approved royal hero.
Preserve all wallet / XP / diamonds / friend / purchase / map code by construction.
Legacy saved avatar IDs 0..2 migrate to hidden 6..8 so existing selections
remain visible without changing the three new choices 0..2.
"""
from pathlib import Path
import hashlib

file = Path('lib/main.dart')
manifest = Path('pubspec.yaml')
assert file.exists() and manifest.exists(), 'SAFE_STOP: source/pubspect not found'
old = file.read_text(encoding='utf-8')
pub = manifest.read_text(encoding='utf-8')
marker = '// DEDA_ROYAL_THREE_AVATARS_STEP1_2026_10_17'
assert marker not in old, 'SAFE_STOP: asset stage already applied'
assert '// DEDA_ROYAL_PROFILE_HERO_LAYOUT_ONLY_2026_10_17' in old, 'SAFE_STOP: first royal hero patch absent'

expected_files = {
    'deda_avatar_male_royal.jpg': ('1b3e8457e2a9f05e665f46b442f3ec2100c6d399', 384434),
    'deda_avatar_female_royal.jpg': ('4d77fd546aaab9aec9b46c2ab0c645e3044ca488', 337062),
    'deda_avatar_couple_royal.jpg': ('e3763118b218fc51d2697bb1ba96e9d8c0b8d864', 536304),
}
for basename, (expected, size) in expected_files.items():
    path = Path('assets/deda_royal_avatars') / basename
    assert path.is_file(), 'SAFE_STOP: original asset missing: '+str(path)
    data = path.read_bytes()
    real = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\x00'+data).hexdigest()
    assert real == expected and len(data)==size and data.startswith(b'\xff\xd8\xff'), 'SAFE_STOP: approved original image mismatch: '+basename


def replace_exact(haystack, target, value, tag, count=1):
    found = haystack.count(target)
    assert found == count, f'SAFE_STOP: {tag} found {found}, wanted {count}'
    return haystack.replace(target, value, count)

# No image synthesis and no alternative artwork. The exact three original
# high-resolution JPEG byte arrays are included as immutable Flutter assets.
old_portrait = '''  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: CustomPaint(
          painter: _DedaAvatarPainter(style),
        ),
      ),
    );
  }
}

class _DedaAvatarPainter'''
new_portrait = '''  // DEDA_ROYAL_THREE_AVATARS_STEP1_2026_10_17
  // 0 male / 1 female / 2 couple = exact user-approved 1536px portraits.
  // 3..5 are unchanged existing classic options.
  // 6..8 preserve owners who had picked the original classic styles 0..2.
  static const List<String> royalImageAssets = <String>[
    'assets/deda_royal_avatars/deda_avatar_male_royal.jpg',
    'assets/deda_royal_avatars/deda_avatar_female_royal.jpg',
    'assets/deda_royal_avatars/deda_avatar_couple_royal.jpg',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: style >= 0 && style < royalImageAssets.length
            ? Image.asset(
                royalImageAssets[style],
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                // 4 device pixels per logical pixel: sharp at the actual
                // display size without keeping three 1536px decoded buffers.
                cacheWidth: (size * 4).round().clamp(384, 1536).toInt(),
              )
            : CustomPaint(
                painter: _DedaAvatarPainter(style >= 6 && style <= 8
                    ? style - 6
                    : style),
              ),
      ),
    );
  }
}

class _DedaAvatarPainter'''
old = replace_exact(old, old_portrait, new_portrait, 'portrait renderer')

# Migrate only the user's old cosmetic selection; never touch any other prefs,
# payment records, identifiers, level, XP, social data, or wallet keys.
profileKey = '''  static String _profileAvatarKey(String phoneValue) =>
      'deda_profile_avatar_v1_${phoneValue.replaceAll(RegExp(r'[^0-9]'), '')}';'''
append = profileKey + '''

  static String _avatarMigrationKey(String phoneValue) =>
      'deda_royal_avatar_choice_migrated_v1_${phoneValue.replaceAll(RegExp(r'[^0-9]'), '')}';

  static Future<int> _loadRoyalSafeAvatarStyle(
      SharedPreferences prefs, String phoneValue) async {
    final key = _profileAvatarKey(phoneValue);
    final migration = _avatarMigrationKey(phoneValue);
    final oldChoice = prefs.getInt(key);
    if (prefs.getBool(migration) == true) {
      return (oldChoice ?? 0).clamp(0, 8).toInt();
    }
    // Existing accounts with an explicitly stored legacy style 0,1,2
    // keep the EXACT cartoon choice at hidden indexes 6,7,8.
    final safeChoice = oldChoice != null && oldChoice >= 0 && oldChoice <= 2
        ? oldChoice + 6
        : (oldChoice ?? 0).clamp(0, 8).toInt();
    if (oldChoice != null && safeChoice != oldChoice) {
      await prefs.setInt(key, safeChoice);
    }
    await prefs.setBool(migration, true);
    return safeChoice;
  }'''
old = replace_exact(old, profileKey, append, 'legacy avatar prefs key')
old = replace_exact(old,
    'profileAvatarStyle = prefs.getInt(_profileAvatarKey(phone)) ?? 0;',
    'profileAvatarStyle = await _loadRoyalSafeAvatarStyle(prefs, phone);',
    'local account avatar load')
old = replace_exact(old,
    'profileAvatarStyle = prefs.getInt(_profileAvatarKey(normalizedPhone)) ?? 0;',
    'profileAvatarStyle = await _loadRoyalSafeAvatarStyle(prefs, normalizedPhone);',
    'account switch avatar load')
old = replace_exact(old,
    'profileAvatarStyle = avatarStyle.clamp(0, 5).toInt();',
    'profileAvatarStyle = avatarStyle.clamp(0, 8).toInt();',
    'legacy choice write safety')
# Save the migration marker together with normal appearance updates, ensuring
# later reloads won't ever reinterpret a freshly selected royal style as legacy.
old = replace_exact(old,
    'prefs.setInt(_profileAvatarKey(phone), profileAvatarStyle),',
    'prefs.setInt(_profileAvatarKey(phone), profileAvatarStyle),\n      prefs.setBool(_avatarMigrationKey(phone), true),',
    'new choice migration marker')

# Royal gallery: first three new premium-quality portraits, next three classic.
old = replace_exact(old,
    "'3 شخصيات ذكورية و3 أنثوية بألوان شعر وملامح مختلفة.',\n                'Three male and three female portraits with different hair and features.',",
    "'3 صور ملكية مجانية، مع بقاء 3 شخصيات كلاسيكية للاختيار.',\n                'Three free royal portraits and three classic choices.',",
    'edit profile image description')

old_type='''                                  index < 3
                                      ? dedaText('ذكوري', 'Male')
                                      : dedaText('أنثوي', 'Female'),'''
new_type='''                                  index == 0
                                      ? dedaText('ذكوري', 'Male')
                                      : index == 1
                                          ? dedaText('أنثوي', 'Female')
                                          : index == 2
                                              ? dedaText('ثنائي', 'Couple')
                                              : dedaText('كلاسيكي', 'Classic'),'''
old = replace_exact(old,old_type,new_type,'portrait tile labels')
# Existing gallery selection styling, free/locked frame behavior, and purchases remain unchanged.

# Make legacy selection explicit to avoid silent replacement when editing
# unrelated account information; they can choose new royal style intentionally.
gallery_end = '''            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    dedaText('إطارات DEDA', 'DEDA frames'),'''
legacyNotice = '''            if (_avatarStyle >= 6 && _avatarStyle <= 8) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                dedaText(
                  'صورتك الكلاسيكية السابقة محفوظة. تگدر تبقيها أو تختار واحدة من الصور الجديدة.',
                  'Your previous classic portrait is preserved; choose a new portrait only if you want to change it.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF536577),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
''' + gallery_end
old = replace_exact(old, gallery_end, legacyNotice, 'gallery to frame separation')

# Top-left edit button replaces duplicate copy action; keep the working ID
# copy button inside the ID chip. Remove the bottom floating pencil only from
# the profile hero, keeping online-status dot and frame painter.
appbar = '''          IconButton(
            tooltip: dedaText('نسخ المعرف', 'Copy ID'),
            onPressed: _copyDedaId,
            icon: const Icon(Icons.copy_rounded),
          ),'''
newbar = '''          IconButton(
            tooltip: dedaText('تعديل الملف', 'Edit profile'),
            onPressed: _openEditProfile,
            icon: const Icon(Icons.edit_rounded),
          ),'''
old = replace_exact(old,appbar,newbar,'profile appbar edit action')
# Replace only _avatar in the accepted royal profile class, anchored by next
# method. Do not alter any other avatar/listener or edit action.
start=old.index('  Widget _avatar(int frameStyle, double size) {',old.index('class _DedaProfilePhase2PageState'))
end=old.index('  Widget _miniPill({',start)
section=old[start:end]
# In nested widget tree, removing up to first closing Positioned is unsafe;
# use the full pre-approved block from the actual 100340 source.
pen = '''          Positioned(
            right: -1,
            bottom: 1,
            child: Material(
              color: _navy,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openEditProfile,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
'''
if section.count(pen)!=1:
    raise SystemExit('SAFE_STOP: royal hero pen block changed')
old=old[:start]+section.replace(pen,'',1)+old[end:]

# Show the SAME real live/current ID in edit profile, without a fake replace
# button: the global ownership-verified ID-switching feature is a separate
# future implementation and must never pretend to be usable.
previewEnd = '''            const SizedBox(height: 18),
            _sectionTitle(
              dedaText(
                'الصورة الشخصية من داخل DEDA','''
idCard = '''            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD5DEDC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    dedaText('معرّف DEDA الحالي', 'Current DEDA ID'),
                    style: const TextStyle(
                      fontSize: 13, color: Color(0xFF5C6872),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim(),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: Color(0xFF213C62),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dedaText(
                      'المعرّفات المميزة المملوكة: تفعيلها يتطلب ربطًا موثقًا في مرحلة مستقلة.',
                      'Owned premium ID activation requires verified linking in a separate stage.',
                    ),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF71808A)),
                  ),
                ],
              ),
            ),
''' + previewEnd
old=replace_exact(old, previewEnd, idCard, 'edit page current ID card')

# Change only app asset manifest (3 paths). No new packages/dependencies.
manifest_anchor='    - assets/deda_home_bg.jpg\n'
for basename in expected_files:
    assert f'assets/deda_royal_avatars/{basename}' not in pub
new_pub=replace_exact(pub,manifest_anchor,manifest_anchor+''.join(
    '    - assets/deda_royal_avatars/'+n+'\n' for n in expected_files),
    'pubspec asset declarations')

# Guard rails: byte-for-byte unchanged protected business/accounting segments.
def protected(src, begin, end):
    first=src.find(begin)
    last=src.find(end,first)
    assert first>=0 and last>first, 'SAFE_STOP: protected accounting segment missing '+begin
    return src[first:last]
for seg1,seg2 in (
    ('class DedaDiamondsWallet {','class DedaAccountHubPage extends StatefulWidget {'),
    ('class DedaSocialProgressWallet {','class DedaStyleInventorySnapshot {'),
):
    if seg1 in file.read_text() and seg2 in file.read_text():
        assert protected(file.read_text(),seg1,seg2)==protected(old,seg1,seg2), 'SAFE_STOP: wallet accounting logic changed'
for needle in ('DedaTaskEngine.totalPointsNotifier','DedaDiamondsWallet.balanceNotifier',
               'DedaSocialProgressWallet.xpNotifier','dedaProfileVisibleDiamonds(',
               'DedaStyleInventory.activeBadgeNotifier'):
    assert old.count(needle)>=file.read_text().count(needle), 'SAFE_STOP: protected balance/level notifier missing: '+needle
assert old.count('DedaAvatarPortrait(')>=3
assert old.count('DedaProfileFramePreview(')>=1
assert old.count('DedaFramedAvatar(')>=3

file.write_text(old,encoding='utf8')
manifest.write_text(new_pub,encoding='utf8')
print('PASS: royal 3 portraits original bytes, legacy 0..2 migrated to 6..8, global portrait rendering, top edit, current ID label')
print('PASS: same wallet, level, diamonds and friend logic; original frame logic unchanged')