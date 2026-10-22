#!/usr/bin/env python3
"""Point09: prevent stale profile-shop frame equip after an async account swap.

Stage ONLY against the real reconstructed Flutter app, after the existing
async wallet/account and appearance guards. No changes to purchase, wallet,
backend rights, points, original badge ids or original profile preference keys.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = 'DEDA_100377_POINT09_EQUIP_FRAME_ACCOUNT_SNAPSHOT'
START = 'class _DedaStylePageState extends State<DedaStylePage> {'
END = '  Future<void> _activateBadge(int index) async {'

OLD = """  Future<void> _equipFrame(int index) async {
    final inventory = _inventory;
    if (inventory == null || !inventory.owned.contains('frame_$index')) return;
    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    DedaProfileAppearanceState.frameNotifier.value = index;
    await dedaEnsurePersonalSocialSession();
    if (mounted) setState(() {});
  }

"""
NEW = """  Future<void> _equipFrame(int index) async {
    // DEDA_100377_POINT09_EQUIP_FRAME_ACCOUNT_SNAPSHOT
    // UI inventory may belong to the previous account after sign-out.
    // Verify the CURRENT account's stored entitlement before switching.
    final accountPhone = DedaPreferences.phone;
    final accountKey = DedaBackend.accountKeyForPhone(accountPhone).trim();
    final firebaseReady = Firebase.apps.isNotEmpty;
    final accountUid = firebaseReady
        ? FirebaseAuth.instance.currentUser?.uid : null;
    bool sameOwner() =>
        mounted && accountPhone.trim().isNotEmpty &&
        DedaPreferences.phone == accountPhone &&
        DedaBackend.accountKeyForPhone(accountPhone).trim() == accountKey &&
        Firebase.apps.isNotEmpty == firebaseReady &&
        (firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null) ==
            accountUid;
    if (!sameOwner() || (firebaseReady && accountUid == null)) return;
    final freshInventory = await DedaStyleInventory.load();
    if (!sameOwner() || !freshInventory.owned.contains('frame_$index')) {
      return;
    }
    await DedaPreferences.setProfileAppearance(
      avatarStyle: DedaPreferences.profileAvatarStyle,
      frameStyle: index,
      backgroundStyle: DedaPreferences.profileBackgroundStyle,
    );
    // The setter may have returned without saving due to account switching.
    // Never update the global notifier with an obsolete or unsaved frame.
    if (!sameOwner() || DedaPreferences.profileFrameStyle != index) return;
    DedaProfileAppearanceState.frameNotifier.value = index;
    await dedaEnsurePersonalSocialSession();
    if (sameOwner()) setState(() {});
  }

"""

def patch(src: str) -> str:
    if MARK in src:
        if src.count(MARK) != 1 or src.count('final freshInventory = await DedaStyleInventory.load();') != 1:
            raise ValueError('SAFE_STOP_POINT09_EQUIP_PARTIAL_PATCH')
        return src
    if src.count(START) != 1:
        raise ValueError('SAFE_STOP_POINT09_EQUIP_NOT_REAL_PAGE')
    a = src.index(START)
    b = src.find('\nclass ', a + len(START))
    if b < a:
        raise ValueError('SAFE_STOP_POINT09_EQUIP_CLASS_BOUNDARY')
    body = src[a:b]
    if body.count(OLD) != 1 or body.count(END) != 1:
        raise ValueError('SAFE_STOP_POINT09_EQUIP_SOURCE_DRIFT')
    body = body.replace(OLD, NEW, 1)
    if body.count(MARK) != 1 or body.count('sameOwner()') < 5:
        raise ValueError('SAFE_STOP_POINT09_EQUIP_INCOMPLETE')
    return src[:a] + body + src[b:]


if __name__ == '__main__':
    before = MAIN.read_text(encoding='utf-8')
    after = patch(before)
    if after == before:
        raise SystemExit('SAFE_STOP_POINT09_EQUIP_ALREADY_STAGED')
    MAIN.write_text(after, encoding='utf-8')
    print('PASS_POINT09_FRAME_EQUIP_RELOADS_OWNER_ENTITLEMENT_AFTER_AWAIT')
    print('PASS_POINT09_NO_STALE_GLOBAL_FRAME_NOTIFIER_AFTER_ACCOUNT_SWITCH')
    print('NO_SPEND_NO_FIREBASE_WRITE_NO_PLAY_OR_APK')
