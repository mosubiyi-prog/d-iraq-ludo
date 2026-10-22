#!/usr/bin/env python3
"""Point09 guarded ONLY-LOCAL profile appearance save on reconstructed DEDA.

A delayed SharedPreferences await must never write style choices under the
newly signed-in account. This does NOT restore cloud appearance, validate
paid ownership, migrate per-phone history, or modify wallets/Firebase.
"""
from pathlib import Path

MAIN = Path('lib/main.dart')
MARK = '// DEDA_100377_POINT09_APPEARANCE_ASYNC_ACCOUNT_SCOPE'
ANCHOR = '  static Future<void> setProfileAppearance({'
STOP = '  static Future<void> setVoiceEnabled(bool enabled) async {'
ORIGINAL = """  static Future<void> setProfileAppearance({
    required int avatarStyle,
    required int frameStyle,
    required int backgroundStyle,
  }) async {
    profileAvatarStyle = avatarStyle.clamp(0, 8).toInt();
    profileFrameStyle = frameStyle.clamp(0, 18).toInt();
    profileBackgroundStyle = backgroundStyle.clamp(0, 8).toInt();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_profileAvatarKey(phone), profileAvatarStyle),
      prefs.setBool(_avatarMigrationKey(phone), true),
      prefs.setInt(_profileFrameKey(phone), profileFrameStyle),
      prefs.setInt(
        _profileBackgroundKey(phone),
        profileBackgroundStyle,
      ),
    ]);
  }

"""
REPLACEMENT = """  // DEDA_100377_POINT09_APPEARANCE_ASYNC_ACCOUNT_SCOPE
  // Snapshot current local account AND Firebase UID before any asynchronous
  // preference work. A second account must never inherit the first account's
  // avatar/frame/background selection, even if sign-in happens mid-await.
  static String? _appearanceCurrentUid() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setProfileAppearance({
    required int avatarStyle,
    required int frameStyle,
    required int backgroundStyle,
  }) async {
    final savePhone = phone;
    final saveUid = _appearanceCurrentUid();
    if (!isLoggedIn || savePhone.trim().isEmpty) return;
    final requestedAvatar = avatarStyle.clamp(0, 8).toInt();
    final requestedFrame = frameStyle.clamp(0, 18).toInt();
    final requestedBackground = backgroundStyle.clamp(0, 8).toInt();
    final prefs = await SharedPreferences.getInstance();
    if (!isLoggedIn || phone != savePhone ||
        _appearanceCurrentUid() != saveUid) return;
    // Capture ORIGINAL phone in every key, never mutable DedaPreferences.phone.
    // All existing per-phone preference keys and old saved items are retained.
    await Future.wait([
      prefs.setInt(_profileAvatarKey(savePhone), requestedAvatar),
      prefs.setBool(_avatarMigrationKey(savePhone), true),
      prefs.setInt(_profileFrameKey(savePhone), requestedFrame),
      prefs.setInt(_profileBackgroundKey(savePhone), requestedBackground),
    ]);
    if (!isLoggedIn || phone != savePhone ||
        _appearanceCurrentUid() != saveUid) return;
    // Don't repaint the newly signed-in user's in-memory profile style.
    profileAvatarStyle = requestedAvatar;
    profileFrameStyle = requestedFrame;
    profileBackgroundStyle = requestedBackground;
  }

"""

def patch(src: str) -> str:
    if MARK in src:
        if (src.count(MARK) != 1 or src.count(ANCHOR) != 1 or
                src.count('_appearanceCurrentUid()') < 3 or
                src.count('_profileAvatarKey(savePhone)') != 1):
            raise ValueError('SAFE_STOP_P09_APPEARANCE_PARTIAL_PATCH')
        return src
    if src.count('class DedaPreferences {') != 1 or src.count(ANCHOR) != 1:
        raise ValueError('SAFE_STOP_P09_MISSING_PREFERENCES')
    if src.count(ORIGINAL) != 1 or src.count(STOP) != 1:
        raise ValueError('SAFE_STOP_P09_APPEARANCE_ORIGINAL_DRIFT')
    begin=src.index(ANCHOR)
    end=src.index(STOP,begin)
    if src[begin:end] != ORIGINAL:
        raise ValueError('SAFE_STOP_P09_APPEARANCE_EXTRA_CODE_OR_DRIFT')
    src=src[:begin]+REPLACEMENT+src[end:]
    if src.count(MARK) != 1 or src.count(ANCHOR) != 1:
        raise ValueError('SAFE_STOP_P09_APPEARANCE_PATCH_INCOMPLETE')
    return src

if __name__ == '__main__':
    old=MAIN.read_text(encoding='utf-8')
    new=patch(old)
    if new == old:
        raise SystemExit('SAFE_STOP_P09_APPEARANCE_ALREADY_STAGED')
    MAIN.write_text(new,encoding='utf-8')
    print('PASS_POINT09_ASYNC_PROFILE_STYLE_SAVE_PHONE_AND_UID_SCOPED')
    print('PASS_EXISTING_AVATAR_MIGRATION_AND_LEGACY_PREFS_KEYS_PRESERVED')
    print('NO_FIREBASE_WRITE_NO_CLOUD_RESTORE_NO_WALLET_OR_PURCHASE_CHANGE')
