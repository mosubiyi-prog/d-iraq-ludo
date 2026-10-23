"""Apply owner18 ONLY after exact 100378 reconstruction and its old checks.

No map, navigation, login, places, tasks, ads or gift transaction changes.
Keeps original per-account storage keys, native wallet and identity routing.
"""
from pathlib import Path
import hashlib
import json

MAIN = Path('lib/main.dart')

def one(s, old, new):
    if s.count(old) != 1:
        raise ValueError('owner18 source drift: ' + old[:100])
    return s.replace(old, new, 1)

def section(s, start, end, fn):
    a = s.index(start)
    b = s.index(end, a + len(start))
    return s[:a] + fn(s[a:b]) + s[b:]

def inventory(s):
    # Preserve the original native inventory implementation and local keys.
    anchor = "    // Earlier DEDA builds gave frame 1/2 as free defaults."
    cloud = """    // OWNER18: merge the same account's native-shop backup, never replace
    // local historical ownership or copy another account's chosen badge.
    final original = DedaBackend.personalShareIdForPhone(phone).trim();
    if (uid != null) {
      try {
        final remote = await DedaOwner18Cosmetics.read(original);
        if (!_badgeAccountSame(phone, scope, uid)) return _emptyBadgeInventory();
        final remoteOwned = remote['ownedStyles'];
        if (remoteOwned is List) owned.addAll(remoteOwned.whereType<String>());
        final remoteActive = remote['activeBadges'];
        final pending = prefs.getBool('deda_style_backup_pending_$scope') == true;
        if (!pending && remoteActive is List) {
          for (final id in remoteActive.whereType<String>()) {
            if (owned.contains(id) && dedaStyleBadgeIds.contains(id)) {
              selectedBadge = id;
              break;
            }
          }
        }
        // First backup uses the SAME historical native ownership, not a new
        // purchase. Union never removes another device's bought items.
        await DedaOwner18Cosmetics.backupInventory(original, owned,
          !pending && remoteActive is List ? remoteActive.whereType<String>().toSet()
            : {selectedBadge});
        if (_badgeAccountSame(phone, scope, uid)) {
          await prefs.remove('deda_style_backup_pending_$scope');
        }
      } catch (_) {
        // Keep the current account's exact local inventory while offline.
      }
    }

"""
    s = one(s, anchor, cloud + anchor)
    old = '    return saved && _badgeAccountSame(phone, scope, uid);'
    s = one(s, old, """    if (saved) await prefs.setBool('deda_style_backup_pending_$scope', true);
    if (saved && uid != null && _badgeAccountSame(phone, scope, uid)) {
      try {
        await DedaOwner18Cosmetics.backupInventory(
          DedaBackend.personalShareIdForPhone(phone).trim(),
          snapshot.owned, snapshot.activeBadges);
        if (_badgeAccountSame(phone, scope, uid)) {
          await prefs.remove('deda_style_backup_pending_$scope');
        }
      } catch (_) {
        // The native local purchase stays saved for retry on the next load.
      }
    }
    return saved && _badgeAccountSame(phone, scope, uid);""")
    return s

RESTORE = """  // OWNER18: only avatar/frame/background preferences are synchronized.
  static Future<void> restoreProfileAppearanceFromAccount() async {
    final ownerPhone = phone;
    final uid = _appearanceCurrentUid();
    if (ownerPhone.trim().isEmpty || uid == null) return;
    final original = DedaBackend.personalShareIdForPhone(ownerPhone).trim();
    bool same() => phone == ownerPhone && _appearanceCurrentUid() == uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = 'deda_appearance_cloud_pending_$ownerPhone';
      if (!same()) return;
      if (prefs.getBool(pendingKey) == true) {
        await DedaOwner18Cosmetics.saveAppearance(original,
          avatar: profileAvatarStyle, frame: profileFrameStyle,
          background: profileBackgroundStyle);
        if (same()) await prefs.remove(pendingKey);
        return;
      }
      final remote = await DedaOwner18Cosmetics.read(original);
      if (!same()) return;
      if (remote['avatar'] is! int || remote['frame'] is! int ||
          remote['background'] is! int) {
        await DedaOwner18Cosmetics.saveAppearance(original,
          avatar: profileAvatarStyle, frame: profileFrameStyle,
          background: profileBackgroundStyle);
        return;
      }
      final avatar = (remote['avatar'] as int).clamp(0, 8).toInt();
      final frame = (remote['frame'] as int).clamp(0, 18).toInt();
      final background = (remote['background'] as int).clamp(0, 8).toInt();
      if (frame >= 6) {
        final item = DedaLabPremiumFrameStyles.byProfileStyle(frame);
        if (item == null || !await DedaOwner18FrameCheckout.isOwned(
            originalId: original, frameId: item.id)) return;
      }
      if (!same()) return;
      await Future.wait([
        prefs.setInt(_profileAvatarKey(ownerPhone), avatar),
        prefs.setBool(_avatarMigrationKey(ownerPhone), true),
        prefs.setInt(_profileFrameKey(ownerPhone), frame),
        prefs.setInt(_profileBackgroundKey(ownerPhone), background),
      ]);
      if (!same()) return;
      profileAvatarStyle = avatar;
      profileFrameStyle = frame;
      profileBackgroundStyle = background;
      DedaProfileAppearanceState.syncFromPreferences();
    } catch (_) {
      // A network failure never clears a local selected image or paid frame.
    }
  }

"""

def preferences(s):
    anchor = '  static Future<void> setVoiceEnabled(bool enabled) async {'
    s = one(s, anchor, RESTORE + anchor)
    old = '    profileBackgroundStyle = requestedBackground;'
    new = old + """
    final pendingKey = 'deda_appearance_cloud_pending_$savePhone';
    await prefs.setBool(pendingKey, true);
    if (phone != savePhone || _appearanceCurrentUid() != saveUid) return;
    if (saveUid != null) {
      try {
        await DedaOwner18Cosmetics.saveAppearance(
          DedaBackend.personalShareIdForPhone(savePhone).trim(),
          avatar: requestedAvatar, frame: requestedFrame,
          background: requestedBackground);
        if (phone == savePhone && _appearanceCurrentUid() == saveUid) {
          await prefs.remove(pendingKey);
        }
      } catch (_) {
        // Retain pending backup; next signed-in foreground retries it.
      }
    }"""
    return one(s, old, new)

def hero(s):
    s = one(s, "'مستوى ذهبي $level'",
        "'مستوى ${DedaOwner18Rank.forLevel(level).nameAr} $level'")
    s = one(s, "'Gold level $level'",
        "'${DedaOwner18Rank.forLevel(level).nameEn} level $level'")
    start = s.index('                        // This is the already-equipped badge, NOT a fake badge.')
    end = s.index('\n                      ],', start)
    s = s[:start] + """                        // OWNER18: rank badge follows the unchanged XP-to-level calculation.
                        ValueListenableBuilder<int>(
                          valueListenable: DedaSocialProgressWallet.xpNotifier,
                          builder: (context, xp, _) => DedaOwner18LevelBadge(
                            level: DedaSocialProgressWallet.levelForXp(
                              xp.clamp(0, 1 << 30).toInt()),
                            size: 58,
                          ),
                        ),""" + s[end:]
    return s

def store(s):
    s = one(s, '    final inventory = await DedaStyleInventory.load();',
        """    final inventory = await DedaStyleInventory.load();
    var savedStyles = <String>{};
    try {
      final remote = await DedaOwner18Cosmetics.read(originalId);
      final list = remote['ownedStyles'];
      if (list is List) savedStyles = list.whereType<String>().toSet();
    } catch (_) {}""")
    # Native-shop purchases are account-backed, not falsely described as
    # server-attested historical payment receipts.
    s = s.replace('proof: DedaMyStoreProof.serverVerified,\n            receiptKind: \'purchase\',',
                  'proof: DedaMyStoreProof.accountSaved,\n            receiptKind: \'purchase\',')
    s = one(s, 'proof: DedaMyStoreProof.deviceSaved,',
        "proof: i == 0 ? DedaMyStoreProof.basicFree\n          : savedStyles.contains(badgeId) ? DedaMyStoreProof.accountSaved\n          : DedaMyStoreProof.deviceSaved,\n        receiptKind: i == 0 ? null : 'purchase',")
    # Legacy native paid frame styles 1 and 2 are NOT free catalog entries.
    anchor = '    for (var i = 0; i < dedaStyleBadgeIds.length; i++) {'
    s = one(s, anchor, """    for (final style in [1, 2]) {
      final item = 'frame_$style';
      if (!inventory.owned.contains(item)) continue;
      items.add(DedaMyStoreItem(id: item, label: 'إطار ${dedaStyleName(style)}',
        section: DedaMyStoreSection.frames,
        proof: savedStyles.contains(item) ? DedaMyStoreProof.accountSaved
          : DedaMyStoreProof.deviceSaved,
        receiptKind: 'purchase', active: frameStyle == style));
    }
""" + anchor)
    return s

def native_wallet(s):
    # Freeze exactly the original wallet and user before its first await.
    start = '  static Future<bool> spend(int amount) async {'
    a = s.index(start)
    b = s.index('  static Future<void> _write(', a)
    spend = s[a:b]
    anchor = '    if (amount <= 0) return true;'
    spend = one(spend, anchor, anchor + """
    final ownerPhone = DedaPreferences.phone;
    final ownerKey = _prefsKey();
    final ownerUid = Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
    bool sameOwner() => DedaPreferences.phone == ownerPhone && _prefsKey() == ownerKey &&
      (Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid) == ownerUid;
""")
    spend = one(spend, '    final current = await load();',
      '    final current = await load();\n    if (!sameOwner()) return false;')
    spend = spend.replace('phone: DedaPreferences.phone,', 'phone: ownerPhone,')
    spend = one(spend, '        _generalManagerPersonalBalance =\n',
      '        final confirmedManagerBalance =\n')
    spend = one(spend, '        generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;',
      '        if (!sameOwner()) return false;\n'
      '        _generalManagerPersonalBalance = confirmedManagerBalance;\n'
      '        generalManagerPersonalNotifier.value = _generalManagerPersonalBalance;')
    spend = spend.replace('DedaBackend.personalShareIdForPhone(DedaPreferences.phone)',
      'DedaBackend.personalShareIdForPhone(ownerPhone)')
    old = """    await _write(
      prefs,
      balance: nextLocal,
      viewsToday: current.viewsToday,
      dayKey: current.dayKey,
    );"""
    spend = one(spend, old, """    if (!sameOwner()) return false;
    final saved = await prefs.setString(ownerKey, jsonEncode(<String, dynamic>{
      'balance': nextLocal, 'viewsToday': current.viewsToday, 'day': current.dayKey,
    }));
    if (!saved || !sameOwner()) return false;""")
    return s[:a] + spend + s[b:]

def main():
    src = MAIN.read_text()
    if '// DEDA_OWNER18_FINAL_INTEGRATION_2026_10_23' in src:
        raise ValueError('owner18 already applied')
    original = src
    # Reference image geometry and old portrait renderer are preserved.
    manifest = json.loads(Path('docs/DEDA_OWNER18_APPROVED_AVATARS_2026-10-23.json').read_text())
    images = []
    for row in manifest['avatars']:
        assert hashlib.sha256(Path(row['asset']).read_bytes()).hexdigest() == row['sha256']
        assert row['dimensions'] == [1536, 1536]
        images.append(row['asset'])
    assert len(images) == 3 and manifest['inner_display'] == [111, 111]
    anchor = "import 'package:flutter/material.dart';"
    src = one(src, anchor, anchor + "\n// DEDA_OWNER18_FINAL_INTEGRATION_2026_10_23\n"
        "import 'deda_owner18_cosmetics.dart';\n"
        "import 'deda_owner18_frame_checkout.dart';\n"
        "import 'deda_owner18_frame_purchase_action.dart';\n"
        "import 'deda_owner18_level_badges.dart';")
    src = src.replace("import 'deda_lab_frame_purchase_action.dart';\n", '')
    src = src.replace('DedaLabFramePurchaseAction(', 'DedaOwner18FramePurchaseAction(')
    src = src.replace('DedaOwner18FramePurchaseAction(\n', 'DedaOwner18FramePurchaseAction(\n                                    width: cell,\n')
    src = src.replace('DedaLabFrameSecureCheckout.', 'DedaOwner18FrameCheckout.')
    def portrait(s):
        anchor = '  @override\n  Widget build(BuildContext context) {'
        extra = '  static const allImageAssets = <String>[...royalImageAssets,\n'
        extra += ''.join("    '" + p + "',\n" for p in images) + '  ];\n\n'
        s = one(s, anchor, extra + anchor)
        s = one(s, 'style < royalImageAssets.length', 'style < allImageAssets.length')
        return one(s, 'royalImageAssets[style]', 'allImageAssets[style]')
    src = section(src, 'class DedaAvatarPortrait extends StatelessWidget {', '\nclass _DedaAvatarPainter', portrait)
    src = src.replace('3 صور ملكية مجانية، مع بقاء 3 شخصيات كلاسيكية للاختيار.',
        '6 صور ملكية مجانية: ثلاث أصلية وثلاث شخصيات جديدة للاختيار.')
    src = src.replace("index == 0\n                                            ?", "index % 3 == 0\n                                            ?")
    src = src.replace('index == 1\n                                                ?', 'index % 3 == 1\n                                                ?')
    src = src.replace("'كلاسيكي', 'Classic'", "'ثنائي', 'Couple'")
    src = src.replace('جرّب 3 إطارات مجانية الآن: ذهبي، زمردي، ووردي أنثوي. والبقية مقفولة للمستقبل.',
        '3 إطارات ملكية مجانية. يمكنك معاينة الإطارات الأخرى وشراء كل إطار مقابل 1,000 ماسة.')
    src = section(src, 'class DedaPreferences {', '\nenum DedaTaskEvent', preferences)
    src = section(src, 'class DedaStyleInventory {', '\nconst List<String> dedaStyleBadgeIds', inventory)
    src = section(src, 'class DedaDiamondsWallet {', '\nclass DedaAccountHubPage', native_wallet)
    src = section(src, '  Widget _profileHeroCard() {', '\n  Widget _avatar(', hero)
    def profile_refresh(s):
        return one(s, '    unawaited(dedaEnsurePersonalSocialSession());', """    final appearanceOwnerPhone = DedaPreferences.phone;
    unawaited(() async {
      try {
        await dedaEnsurePersonalSocialSession();
        if (mounted && DedaPreferences.phone == appearanceOwnerPhone) {
          setState(() {});
        }
      } catch (_) {}
    }());""")
    src = section(src, 'class _DedaProfilePhase2PageState', '\nclass DedaSocialProgressSnapshot', profile_refresh)
    src = section(src, '  Future<void> _openDedaMyStore() async {', '\n  Widget _featureGrid()', store)
    old = """const DedaLevelAchievementsPage(
                        verifiedServerLevel: null,
                        hasVerifiedAccountAndLevel: false,
                      )"""
    src = one(src, old, """DedaOwner18AchievementsPage(
                        level: DedaSocialProgressWallet.levelForXp(
                          DedaSocialProgressWallet.xpNotifier.value),
                        isArabic: DedaLanguageState.isArabic,
                      )""")
    anchor = 'Future<DedaSocialSession> dedaEnsurePersonalSocialSession() async {'
    src = one(src, anchor, anchor + '\n  await DedaPreferences.restoreProfileAppearanceFromAccount();')
    # No generated map/navigation/login/place/task classes may change.
    import re
    def classes(s):
        found = list(re.finditer(r'^(?:abstract )?class (\w+)[^\n]*', s, re.M))
        return {m[1]: s[m.start(): found[i+1].start() if i+1<len(found) else len(s)]
            for i,m in enumerate(found)}
    before, after = classes(original), classes(src)
    allowed = {'DedaAvatarPortrait', 'DedaPreferences', '_DedaEditProfilePageState',
        '_DedaProfilePhase2PageState', 'DedaStyleInventory',
        'DedaIncomingRequestNotifications', 'DedaDiamondsWallet'}
    changed = [name for name in before if before[name] != after.get(name)]
    assert set(changed) <= allowed, 'unrelated class changed: ' + str(set(changed)-allowed)
    MAIN.write_text(src)
    pub = Path('pubspec.yaml')
    s = pub.read_text()
    s = one(s, '    - assets/deda_lab_frames/\n',
        '    - assets/deda_lab_frames/\n    - assets/deda_owner_avatars_20261023/\n')
    pub.write_text(s)
    # The native free catalog must distinguish genuinely paid legacy frames.
    p = Path('lib/deda_100377_profile_free_inventory.dart'); s = p.read_text()
    s = one(s, 'frameChoices = <int>[0, 1, 2, 3, 4, 5]',
        'frameChoices = <int>[0, 3, 4, 5]')
    s = s.replace('الصورة الكلاسيكية 1', 'الصورة الرجالية الزمردية الجديدة')
    s = s.replace('الصورة الكلاسيكية 2', 'الصورة النسائية الزرقاء الجديدة')
    s = s.replace('الصورة الكلاسيكية 3', 'الصورة المشتركة العنابية الجديدة')
    anchor = "      'assets/deda_royal_avatars/deda_avatar_couple_royal.jpg',"
    s = one(s, anchor, anchor + '\n' + ''.join("      '"+p+"',\n" for p in images))
    p.write_text(s)
    p = Path('lib/deda_100377_my_store_page_staged.dart'); s = p.read_text()
    s = one(s, 'enum DedaMyStoreProof { basicFree, deviceSaved, serverVerified }',
        'enum DedaMyStoreProof { basicFree, deviceSaved, accountSaved, serverVerified }')
    s = one(s, '      case DedaMyStoreProof.serverVerified:',
        "      case DedaMyStoreProof.accountSaved:\n"
        "        return _t('مملوك / محفوظ بالحساب', 'Owned / saved to account');\n"
        '      case DedaMyStoreProof.serverVerified:')
    s = s.replace('item.proof == DedaMyStoreProof.serverVerified &&',
        '(item.proof == DedaMyStoreProof.serverVerified || item.proof == DedaMyStoreProof.accountSaved) &&')
    p.write_text(s)
    # Public appearance clamping must allow the same selected native styles.
    p = Path('lib/deda_social_service.dart'); s = p.read_text()
    for field, maximum in [('avatarStyle',8),('frameStyle',18),('backgroundStyle',8)]:
        s = re.sub(r'('+field+r'[^;]{0,160}?)\.clamp\(0, 5\)',
            lambda m: m[1]+f'.clamp(0, {maximum})', s, flags=re.S)
    p.write_text(s)
    print('OWNER18 targeted generated classes changed:', ', '.join(changed))
    print('PASS unrelated generated classes byte-identical; native storage and funds preserved')

if __name__ == '__main__':
    main()
