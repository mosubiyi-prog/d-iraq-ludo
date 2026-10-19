#!/usr/bin/env python3
"""Point16 guarded Flutter Callable transport. Requires approved full 100356 UI.

Does NOT deploy Functions, enable payments, alter balances, or modify the public
checked-in lib/main.dart until explicitly applied to CI-reconstructed source.
Compile-time flag DEDA_PREMIUM_IDS_SERVER_LIVE is FALSE by default.
Before enabling it in a future release: deploy audited callables, configure
Firebase AppCheck, migrate/share alias routes and approve wallet reconciliation.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
MARKER = "// DEDA_INTAKADHA_POINT16_CLIENT_CALLABLE_GATEWAY_CLOSED_BY_DEFAULT"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
IMPORT = "import 'package:cloud_firestore/cloud_firestore.dart';\n"
MORE_IMPORTS = (
    "import 'package:firebase_auth/firebase_auth.dart';\n"
    "import 'package:cloud_functions/cloud_functions.dart';\n"
)
PROFILE_INIT = """  void initState() {
    super.initState();
    DedaPoint14VerifiedBridge.refresh(widget.identifier);
  }"""
PROFILE_INIT_NEW = """  void initState() {
    super.initState();
    DedaPoint16PremiumCallableBridge.configure();
    DedaPoint14VerifiedBridge.refresh(widget.identifier);
  }"""
OWNED_INIT = """  void initState() {
    super.initState();
    Future<void>.microtask(() =>
        DedaPoint15OwnedIdsState.refresh(widget.originalId));
  }"""
OWNED_INIT_NEW = """  void initState() {
    super.initState();
    DedaPoint16PremiumCallableBridge.configure();
    Future<void>.microtask(() =>
        DedaPoint15OwnedIdsState.refresh(widget.originalId));
  }"""
OLD_PAYMENTS = """          onPurchaseVerified: null,
          refreshVerifiedOwnership: null,"""
NEW_PAYMENTS = """          onPurchaseVerified: DedaPoint16PremiumCallableBridge.enabled
              ? DedaPoint16PremiumCallableBridge.checkoutCard
              : null,
          refreshVerifiedOwnership: DedaPoint16PremiumCallableBridge.enabled
              ? () => DedaPoint16PremiumCallableBridge.readOwnedColors(
                  widget.identifier)
              : null,"""

GATEWAY = r'''// DEDA_INTAKADHA_POINT16_CLIENT_CALLABLE_GATEWAY_CLOSED_BY_DEFAULT
// Safe REVIEW ONLY: backend Functions do not exist in production until a
// separate, approved deployment. No UI ownership comes from local rewards.
// Compile-time flag remains false for owner QA APK and all published builds.
class DedaPoint16PremiumCallableBridge {
  static const bool enabled = bool.fromEnvironment(
    'DEDA_PREMIUM_IDS_SERVER_LIVE',
    defaultValue: false,
  );
  static bool _configured = false;

  static void configure() {
    if (!enabled || _configured) return;
    _configured = true;
    DedaPoint14VerifiedBridge.readRemote = readCardState;
    DedaPoint14VerifiedBridge.activateRemote = activateCard;
    DedaPoint15OwnedIdsBridge.verifiedUid =
        () => FirebaseAuth.instance.currentUser?.uid;
    DedaPoint15OwnedIdsBridge.readRemote = readIdentifiers;
    DedaPoint15OwnedIdsBridge.activateRemote = activateIdentifier;
    // Admin grants remain invisible: first-100 protected manifest and
    // admin authority are neither loaded on phone nor inferred locally.
    DedaPoint15OwnedIdsBridge.verifiedGeneralManagerRemote = null;
    DedaPoint15OwnedIdsBridge.grantReservedRemote = null;
  }

  static Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    if (!enabled) throw StateError('premium-identifiers-server-off');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('premium-identifiers-auth-required');
    }
    // The Firebase AppCheck SDK must be configured BEFORE enabling
    // this code. Server callable validates AppCheck and its actual auth.uid.
    final result = await FirebaseFunctions.instance
        .httpsCallable(functionName)
        .call<Map<String, dynamic>>(payload);
    // Do not deliver data from a previous account login to a newer account.
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('premium-identifiers-account-changed');
    }
    return Map<String, dynamic>.from(result.data);
  }

  static DedaPremiumIdCardColor _color(String raw) {
    for (final color in DedaPremiumIdCardColor.values) {
      if (color.name == raw) return color;
    }
    throw StateError('premium-identifiers-unverified-style');
  }

  static DedaPoint14VerifiedSnapshot _cardState(Map<String, dynamic> data) {
    final id = data['identifier'];
    final colors = data['ownedColors'];
    final active = data['activeColor'];
    if (id is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(id) ||
        colors is! List ||
        (active != null && active is! String)) {
      throw StateError('premium-identifiers-invalid-card-response');
    }
    final owned = <DedaPremiumIdCardColor>{};
    for (final raw in colors) {
      if (raw is! String) {
        throw StateError('premium-identifiers-invalid-colors');
      }
      owned.add(_color(raw));
    }
    if (owned.length != colors.length) {
      throw StateError('premium-identifiers-duplicate-colors');
    }
    final chosen = active == null ? null : _color(active as String);
    final checked = DedaPoint14VerifiedSnapshot(
      identifier: id, owned: owned, active: chosen,
    );
    if (!checked.validFor(id)) {
      throw StateError('premium-identifiers-active-card-not-owned');
    }
    return checked;
  }

  static Future<DedaPoint14VerifiedSnapshot> readCardState() async {
    return _cardState(await _call('dedaPremiumReadCards', <String, dynamic>{}));
  }

  static Future<DedaPoint14VerifiedSnapshot> activateCard(
    DedaPremiumIdCardColor color,
  ) async {
    return _cardState(await _call('dedaPremiumActivateCard',
      <String, dynamic>{'color': color.name}));
  }

  static Future<DedaIdCardPurchaseReceipt> checkoutCard(
    DedaPremiumIdCardColor color,
    String requestId,
  ) async {
    final data = await _call('dedaPremiumBuyCard', <String, dynamic>{
      'color': color.name, 'requestId': requestId,
    });
    final transactionId = data['transactionId'];
    final actual = data['color'];
    final charged = data['diamondsCharged'];
    final verified = data['serverConfirmed'];
    final alreadyOwned = data['alreadyOwned'];
    if (transactionId is! String || transactionId.isEmpty ||
        actual != color.name ||
        charged is! int ||
        verified != true || alreadyOwned is! bool ||
        (alreadyOwned && charged != 0) ||
        (!alreadyOwned && charged != 5000)) {
      throw StateError('premium-identifiers-invalid-card-receipt');
    }
    // The UI separately re-fetches server ownership before rendering "Owned".
    return DedaIdCardPurchaseReceipt(
      transactionId: transactionId,
      color: color,
      diamondsCharged: charged,
      serverConfirmed: true,
      alreadyOwned: alreadyOwned,
    );
  }

  static Future<Set<DedaPremiumIdCardColor>> readOwnedColors(
    String expectedOriginal,
  ) async {
    final state = await readCardState();
    if (!state.validFor(expectedOriginal)) {
      throw StateError('premium-identifiers-foreign-account');
    }
    return state.owned;
  }

  static DedaPoint15OwnedIdsSnapshot _identifierState(
    Map<String, dynamic> data,
  ) {
    final uid = data['accountUid'];
    final original = data['originalId'];
    final active = data['activeId'];
    final owned = data['ownedIds'];
    final confirmed = data['serverConfirmed'];
    if (uid is! String || original is! String || active is! String ||
        owned is! List || confirmed != true ||
        owned.any((value) => value is! String)) {
      throw StateError('premium-identifiers-invalid-owned-ids');
    }
    final state = DedaPoint15OwnedIdsSnapshot(
      accountUid: uid,
      originalId: original,
      activeId: active,
      ownedIds: List<String>.from(owned),
      serverConfirmed: true,
    );
    if (!state.validFor(uid, original) ||
        uid != FirebaseAuth.instance.currentUser?.uid) {
      throw StateError('premium-identifiers-invalid-account-ownership');
    }
    return state;
  }

  static Future<DedaPoint15OwnedIdsSnapshot> readIdentifiers() async {
    return _identifierState(await _call(
      'dedaPremiumReadIdentifiers', <String, dynamic>{}));
  }

  static Future<DedaPoint15OwnedIdsSnapshot> activateIdentifier(
    String identifier,
  ) async {
    return _identifierState(await _call(
      'dedaPremiumActivateIdentifier',
      <String, dynamic>{'identifier': identifier},
    ));
  }
}

'''

def apply(source: str) -> str:
    required = [
        "// DEDA_INTAKADHA_POINT14_SERVER_VERIFIED_CARD_USE_2026_10_19",
        "// DEDA_INTAKADHA_POINT15_SERVER_VERIFIED_OWNED_IDENTIFIERS_2026_10_19",
        "class DedaPoint14VerifiedBridge {",
        "class DedaPoint15OwnedIdsBridge {",
        "class DedaPremiumIdCardsManagementPanel",
    ]
    if any(source.count(token) != 1 for token in required) or source.count(ACCOUNT) != 1:
        raise ValueError("SAFE_STOP: exact approved point14+15 reconstructed source required")
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(NEW_PAYMENTS) != 1 or \
                source.count(PROFILE_INIT_NEW) != 2 or \
                source.count(OWNED_INIT_NEW) != 1:
            raise ValueError("SAFE_STOP: incomplete or altered point16 transport")
        return source
    if source.count(IMPORT) != 1 or MORE_IMPORTS.strip() in source or \
            source.count(PROFILE_INIT) != 2 or source.count(OWNED_INIT) != 1 or \
            source.count(OLD_PAYMENTS) != 1:
        raise ValueError("SAFE_STOP: Flutter import, ownership or payment anchors diverged")
    result = source.replace(IMPORT, IMPORT + MORE_IMPORTS, 1)
    result = result.replace(PROFILE_INIT, PROFILE_INIT_NEW)
    result = result.replace(OWNED_INIT, OWNED_INIT_NEW, 1)
    result = result.replace(OLD_PAYMENTS, NEW_PAYMENTS, 1)
    result = result.replace(ACCOUNT, GATEWAY + ACCOUNT, 1)
    if "defaultValue: false" not in GATEWAY:
        raise ValueError("SAFE_STOP: private APK must NEVER enable live server bridge")
    reconstructed = result.replace(GATEWAY, "", 1).replace(NEW_PAYMENTS, OLD_PAYMENTS, 1).replace(
        OWNED_INIT_NEW, OWNED_INIT, 1).replace(PROFILE_INIT_NEW, PROFILE_INIT).replace(
        IMPORT + MORE_IMPORTS, IMPORT, 1)
    if reconstructed != source:
        raise ValueError("SAFE_STOP: point16 source changes leaked into existing app")
    return result

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed app source missing")
    original = MAIN.read_text(encoding="utf8")
    try:
        staged = apply(original)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if staged != original:
        MAIN.write_text(staged, encoding="utf8")
    print("PASS: point16 client callable transport staged; NO live server until explicit flag + deployment")
    print("PASS: server-verified response + account matching, no guessed ownership or local wallet debits")
