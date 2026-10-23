import 'package:shared_preferences/shared_preferences.dart';
import 'deda_backend.dart';
import 'deda_lab_frame_secure_checkout.dart';
import 'deda_owner18_cosmetics.dart';
import 'main.dart' show DedaDiamondsWallet, DedaPreferences;

/// Reuse the original native shop's wallet and spending method. No new
/// currency, billing provider, purchase wallet or Cloud Function is introduced.
class DedaOwner18FrameCheckout {
  static const live = true;
  static const priceDiamonds = 1000;
  static final Map<String, Future<void>> _purchases = {};
  static String _key(String original, String frame) =>
      'deda_native_frame_pending_v1_${original}_$frame';

  static void _item(String frame) {
    if (!DedaLabFrameSecureCheckout.paidFrameIds.contains(frame)) {
      throw ArgumentError('unknown-paid-frame');
    }
  }

  static String _phone(String original) {
    final phone = DedaPreferences.phone;
    if (DedaBackend.personalShareIdForPhone(phone).trim() != original) {
      throw StateError('different-native-wallet-owner');
    }
    return phone;
  }

  static void _same(String uid, String phone) {
    DedaOwner18Cosmetics.sameOwner(uid);
    if (DedaPreferences.phone != phone) throw StateError('account-changed');
  }

  static Future<bool> isOwned(
      {required String originalId, required String frameId}) async {
    _item(frameId);
    final data = await DedaOwner18Cosmetics.read(originalId);
    if (data['ownedFrames'] is List &&
        (data['ownedFrames'] as List).contains(frameId)) return true;
    final phone = _phone(originalId);
    final uid = await DedaOwner18Cosmetics.requireOwner(originalId);
    final prefs = await SharedPreferences.getInstance();
    _same(uid, phone);
    if (prefs.getString(_key(originalId, frameId)) == 'paid') {
      await DedaOwner18Cosmetics.confirmNativeFrame(originalId, frameId);
      _same(uid, phone);
      await prefs.remove(_key(originalId, frameId));
      return true;
    }
    // Preserve any receipt-backed purchases from earlier builds.
    return DedaLabFrameSecureCheckout.isOwned(
        originalId: originalId, frameId: frameId);
  }

  static Future<Set<String>> verifiedOwnedFrameIds(String originalId) async {
    final uid = await DedaOwner18Cosmetics.requireOwner(originalId);
    final data = await DedaOwner18Cosmetics.read(originalId);
    final native = data['ownedFrames'];
    final result = <String>{
      if (native is List)
        ...native
            .whereType<String>()
            .where(DedaLabFrameSecureCheckout.paidFrameIds.contains),
    };
    result.addAll(
        await DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(originalId));
    DedaOwner18Cosmetics.sameOwner(uid);
    return result;
  }

  static Future<int> verifiedPurchaseBalance(String originalId) async {
    final uid = await DedaOwner18Cosmetics.requireOwner(originalId);
    final phone = _phone(originalId);
    await DedaDiamondsWallet.load();
    _same(uid, phone);
    return DedaDiamondsWallet.purchasableBalance;
  }

  static Future<void> buyOnce(
      {required String originalId, required String frameId}) {
    _item(frameId);
    final key = '$originalId/$frameId';
    if (!_purchases.containsKey(key) &&
        _purchases.keys.any((k) => k.startsWith('$originalId/'))) {
      return Future<void>.error(
          StateError('another-frame-purchase-in-progress'));
    }
    return _purchases.putIfAbsent(key, () async {
      try {
        await _buy(originalId, frameId);
      } finally {
        _purchases.remove(key);
      }
    });
  }

  static Future<void> _buy(String original, String frame) async {
    final uid = await DedaOwner18Cosmetics.requireOwner(original);
    final phone = _phone(original);
    if (await isOwned(originalId: original, frameId: frame)) return;
    _same(uid, phone);
    final prefs = await SharedPreferences.getInstance();
    _same(uid, phone);
    final pending = _key(original, frame);
    final state = prefs.getString(pending);
    if (state == 'paid') {
      // Retry account persistence only. Never charge a paid pending item twice.
      await DedaOwner18Cosmetics.confirmNativeFrame(original, frame);
      await prefs.remove(pending);
      return;
    }
    if (state == 'charging') {
      throw StateError('native-payment-unconfirmed-do-not-charge-again');
    }
    // Verify destination BEFORE spending; no offline purchase with a promise
    // of account ownership that cannot currently be saved.
    await DedaOwner18Cosmetics.read(original);
    _same(uid, phone);
    final available = await verifiedPurchaseBalance(original);
    if (available < priceDiamonds) {
      throw StateError('insufficient-native-diamonds');
    }
    // Verify account backup is writable before using the original wallet.
    await DedaOwner18Cosmetics.prepare(original);
    _same(uid, phone);
    if (!await DedaOwner18Cosmetics.beginNativeFrame(original, frame)) return;
    if (!await prefs.setString(pending, 'charging')) {
      await DedaOwner18Cosmetics.cancelUnchargedFrame(original, frame);
      throw StateError('purchase-journal-unavailable');
    }
    _same(uid, phone);
    final paid = await DedaDiamondsWallet.spend(priceDiamonds);
    _same(uid, phone);
    if (!paid) {
      // The original wallet can return false after a lost server response.
      // Preserve the journal: do not risk deducting a second time.
      throw StateError('native-payment-unconfirmed-do-not-charge-again');
    }
    await prefs.setString(pending, 'paid');
    await DedaOwner18Cosmetics.confirmNativeFrame(original, frame);
    _same(uid, phone);
    await prefs.remove(pending);
  }
}
