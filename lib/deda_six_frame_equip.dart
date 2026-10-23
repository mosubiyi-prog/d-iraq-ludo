import 'package:firebase_auth/firebase_auth.dart';
import 'deda_backend.dart';
import 'deda_owner18_cosmetics.dart';
import 'deda_owner18_frame_checkout.dart';
import 'deda_lab_premium_frame_artwork.dart';
import 'main.dart' show DedaPreferences, DedaProfileAppearanceState,
    dedaEnsurePersonalSocialSession;

/// Testable commit ordering. No wallet, purchase or debit callback exists.
class DedaSixFrameCommit {
  static Future<void> run({
    required bool Function() sameAccount,
    required Future<bool> Function() verifyOwnership,
    required Future<void> Function() save,
    required Future<bool> Function() confirm,
    required void Function() publish,
  }) async {
    void guard() { if (!sameAccount()) throw StateError('frame-account-changed'); }
    guard();
    final owned = await verifyOwnership(); guard();
    if (!owned) throw StateError('frame-not-owned');
    await save(); guard();
    final confirmed = await confirm(); guard();
    if (!confirmed) throw StateError('frame-selection-not-confirmed');
    publish();
  }
}

class DedaSixFrameEquip {
  static Future<void> use({required int style, required int avatar,
      required int background}) async {
    final phone = DedaPreferences.phone;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final original = DedaBackend.personalShareIdForPhone(phone).trim();
    final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
    if (phone.trim().isEmpty || uid == null || frame == null) {
      throw StateError('verified-frame-account-required');
    }
    bool same() => DedaPreferences.phone == phone &&
        FirebaseAuth.instance.currentUser?.uid == uid;
    await DedaSixFrameCommit.run(
      sameAccount: same,
      verifyOwnership: () => DedaOwner18FrameCheckout.isOwned(
          originalId: original, frameId: frame.id),
      save: () async {
        // Confirm the server selection before changing any local preference.
        // A failed network save must not become a false Used state on reopen.
        await DedaOwner18Cosmetics.saveAppearance(original,
          avatar: avatar, frame: style, background: background);
        if (!same()) throw StateError('frame-account-changed');
        final saved = await DedaOwner18Cosmetics.read(original);
        if (!same() || saved['frame'] != style || saved['avatar'] != avatar ||
            saved['background'] != background) {
          throw StateError('frame-cloud-selection-not-confirmed');
        }
        await DedaPreferences.setProfileAppearance(avatarStyle: avatar,
          frameStyle: style, backgroundStyle: background);
      },
      confirm: () async {
        final saved = await DedaOwner18Cosmetics.read(original);
        return same() && saved['frame'] == style && saved['avatar'] == avatar &&
            saved['background'] == background &&
            DedaPreferences.profileFrameStyle == style &&
            DedaPreferences.profileAvatarStyle == avatar &&
            DedaPreferences.profileBackgroundStyle == background;
      },
      publish: DedaProfileAppearanceState.syncFromPreferences,
    );
    // Account selection is already confirmed. A transient public appearance
    // sync failure must not undo it or attempt another purchase.
    if (same()) {
      try { await dedaEnsurePersonalSocialSession(); } catch (_) {}
    }
  }
}

class DedaSixFrameOrder {
  static List<int> styles(Set<int> owned) => [
    for (var i = 6; i <= 18; i++) if (owned.contains(i)) i,
    3, 4, 5,
    for (var i = 6; i <= 18; i++) if (!owned.contains(i)) i,
  ];
}
