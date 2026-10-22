#!/usr/bin/env python3
"""Point09: preserve local badge ownership across async account changes."""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = 'DEDA_100377_POINT09_BADGE_ASYNC_ACCOUNT_GUARD'
START = 'class DedaStyleInventory {'
END = '\nconst List<String> dedaStyleBadgeIds = <String>['

def one(source, old, new):
    if source.count(old) != 1:
        raise ValueError('SAFE_STOP_POINT09_BADGE_SOURCE_DRIFT:' + old[:55])
    return source.replace(old, new, 1)

def patch(src):
    if MARK in src:
        if src.count(MARK) != 1 or src.count('_badgeAccountSame(') < 4:
            raise ValueError('SAFE_STOP_POINT09_BADGE_PARTIAL')
        return src
    if src.count(START) != 1 or src.count(END) != 1:
        raise ValueError('SAFE_STOP_POINT09_BADGE_WRONG_REAL_SOURCE')
    a = src.index(START)
    b = src.index(END, a)
    s = src[a:b]
    s = one(s, '  static Future<DedaStyleInventorySnapshot> load() async {',
    """  // DEDA_100377_POINT09_BADGE_ASYNC_ACCOUNT_GUARD
  // A delayed preference operation must NEVER bind the previous owner's
  // purchased badge/style inventory to the next signed-in account.
  static String? _badgeCurrentUid() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static bool _badgeAccountSame(String phone, String scope, String? uid) =>
      DedaPreferences.phone == phone &&
      _scope() == scope &&
      _badgeCurrentUid() == uid;

  static DedaStyleInventorySnapshot _emptyBadgeInventory() =>
      const DedaStyleInventorySnapshot(
        owned: <String>{'frame_0', 'badge_member'},
        activeBadges: <String>{'badge_member'},
      );

  static Future<DedaStyleInventorySnapshot> load() async {""")
    s = one(s,
    """    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key());
    final owned = <String>{'frame_0', 'badge_member'};""",
    """    final phone = DedaPreferences.phone;
    final scope = _scope();
    final uid = _badgeCurrentUid();
    if (phone.trim().isEmpty) return _emptyBadgeInventory();
    final prefs = await SharedPreferences.getInstance();
    if (!_badgeAccountSame(phone, scope, uid)) return _emptyBadgeInventory();
    // Frozen original-account key; never compute _key() after await.
    final raw = prefs.getString('deda_style_inventory_v1_$scope');
    final owned = <String>{'frame_0', 'badge_member'};""")
    s = one(s,
    """    final active = <String>{selectedBadge};
    activeBadgeNotifier.value = selectedBadge;""",
    """    final active = <String>{selectedBadge};
    if (!_badgeAccountSame(phone, scope, uid)) return _emptyBadgeInventory();
    activeBadgeNotifier.value = selectedBadge;""")
    s = one(s,
    """  static Future<void> _save(DedaStyleInventorySnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(),""",
    """  static Future<bool> _save(DedaStyleInventorySnapshot snapshot, {
    required String phone,
    required String scope,
    required String? uid,
  }) async {
    if (!_badgeAccountSame(phone, scope, uid)) return false;
    final prefs = await SharedPreferences.getInstance();
    if (!_badgeAccountSame(phone, scope, uid)) return false;
    final saved = await prefs.setString(
      'deda_style_inventory_v1_$scope',""")
    s = one(s,
    """        'activeBadges': snapshot.activeBadges.toList(),
      }),
    );
  }

  static Future<void> addOwned(String itemId) async {
    final current = await load();""",
    """        'activeBadges': snapshot.activeBadges.toList(),
      }),
    );
    return saved && _badgeAccountSame(phone, scope, uid);
  }

  static Future<void> addOwned(String itemId) async {
    final phone = DedaPreferences.phone;
    final scope = _scope();
    final uid = _badgeCurrentUid();
    if (phone.trim().isEmpty) return;
    final current = await load();
    if (!_badgeAccountSame(phone, scope, uid)) return;""")
    s = one(s,
    """    await _save(DedaStyleInventorySnapshot(
      owned: owned,
      activeBadges: current.activeBadges,
    ));""",
    """    await _save(DedaStyleInventorySnapshot(
      owned: owned,
      activeBadges: current.activeBadges,
    ), phone: phone, scope: scope, uid: uid);""")
    s = one(s,
    """  static Future<void> toggleBadge(String badgeId) async {
    final current = await load();
    if (!current.owned.contains(badgeId)) return;
    final active = <String>{badgeId};
    activeBadgeNotifier.value = badgeId;
    await _save(DedaStyleInventorySnapshot(
      owned: current.owned,
      activeBadges: active,
    ));
  }""",
    """  static Future<void> toggleBadge(String badgeId) async {
    final phone = DedaPreferences.phone;
    final scope = _scope();
    final uid = _badgeCurrentUid();
    if (phone.trim().isEmpty) return;
    final current = await load();
    if (!_badgeAccountSame(phone, scope, uid) ||
        !current.owned.contains(badgeId)) return;
    final active = <String>{badgeId};
    final saved = await _save(DedaStyleInventorySnapshot(
      owned: current.owned,
      activeBadges: active,
    ), phone: phone, scope: scope, uid: uid);
    if (saved && _badgeAccountSame(phone, scope, uid)) {
      activeBadgeNotifier.value = badgeId;
    }
  }""")
    return src[:a] + s + src[b:]

if __name__ == '__main__':
    old = MAIN.read_text(encoding='utf-8')
    new = patch(old)
    if new == old:
        raise SystemExit('SAFE_STOP_POINT09_BADGE_ALREADY_STAGED')
    MAIN.write_text(new, encoding='utf-8')
    print('PASS_POINT09_BADGE_LOCAL_INVENTORY_PHONE_SCOPE_UID_FROZEN')
    print('PASS_SAME_LEGACY_KEY_AND_BADGE_SELECTION_NO_NEW_OWNERSHIP')
    print('NO_FIREBASE_WRITE_NO_WALLET_NO_PUBLISH')
