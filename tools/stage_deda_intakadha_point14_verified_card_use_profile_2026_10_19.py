#!/usr/bin/env python3
"""DEDA point14: server-verified owned cards -> Account 'Use' -> 50px profile.

Staging-only. NO Firebase Functions or rules are deployed and NO production
bridge is installed here: all 3 authenticated bridge callbacks default null.
Cannot use client SharedPreferences, locally selected preview or a purchase
receipt as proof of ownership. Activate only after server persistence + refetch.
"""
from pathlib import Path
import importlib.util

MAIN = Path("lib/main.dart")
BASE = Path(__file__).resolve().parent
POINT6 = "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18"
POINT12 = "// DEDA_INTAKADHA_POINT12_SAFE_CARD_CHECKOUT_UI_2026_10_19"
MARKER = "// DEDA_INTAKADHA_POINT14_VERIFIED_ID_CARD_USE_PROFILE_2026_10_19"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"

def extract(path, name):
    import ast
    root = ast.parse(path.read_text(encoding="utf-8"))
    a = [s.value.value for s in root.body if isinstance(s, ast.Assign)
         and isinstance(s.value, ast.Constant)
         and any(isinstance(t, ast.Name) and t.id == name for t in s.targets)]
    if len(a) != 1:
        raise ValueError("SAFE_STOP: stage material unavailable: " + name)
    return a[0]

def original_call():
    from7 = extract(BASE / "stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py", "NEW_BUTTON")
    if from7.count("            onActivateVerified: null,\n") != 1:
        raise ValueError("SAFE_STOP: stage7 activation gate changed")
    return from7[from7.index("          DedaPremiumIdCardsManagementPanel("):].replace(
        "            onActivateVerified: null,\n",
        "            onActivateVerified: null,\n"
        "            onPurchaseVerified: null,\n"
        "            refreshVerifiedOwnership: null,\n", 1)

OLD_PROFILE = extract(
    BASE / "stage_deda_intakadha_point6_profile_id_slot_2026_10_18.py", "NEW_ID")

NEW_CALL = """          DedaVerifiedIdCardsAccountSection(identifier: originalId),
"""

NEW_PROFILE = """                    DedaVerifiedIdCardsProfileSlot(
                      identifier: id,
                      onCopy: _copyDedaId,
                      width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble(),
                      compact: compact,
                    ),
"""

WIDGETS = r'''// DEDA_INTAKADHA_POINT14_VERIFIED_ID_CARD_USE_PROFILE_2026_10_19
// Authenticated server adapters are installed only after separately reviewed
// production callable integration. Default = no ownership, no activation.
// Never use cached client preference, local purchase receipt or ID preview
// to grant a paid design. The source of truth is the private server ledger.
class DedaVerifiedIdCardSnapshot {
  final String accountUid;
  final String publicId;
  final Set<DedaPremiumIdCardColor> ownedColors;
  final DedaPremiumIdCardColor? activeColor;
  final bool serverConfirmed;

  const DedaVerifiedIdCardSnapshot({
    required this.accountUid,
    required this.publicId,
    required this.ownedColors,
    required this.activeColor,
    required this.serverConfirmed,
  });
}

class DedaVerifiedIdCardsBridge {
  // Future callable MUST derive uid from authenticated request, not input.
  // No implementation in production until separate Function/rules review.
  static String? Function()? authenticatedUid;
  static Future<DedaVerifiedIdCardSnapshot> Function()? readFromServer;
  static Future<DedaVerifiedIdCardSnapshot> Function(
    DedaPremiumIdCardColor color,
  )? activateOnServer;
}

class DedaVerifiedIdCardsState {
  static final ValueNotifier<DedaVerifiedIdCardSnapshot?> notifier =
      ValueNotifier<DedaVerifiedIdCardSnapshot?>(null);
  static int _epoch = 0;
  static String? _lastUid;

  static String? get _uid => DedaVerifiedIdCardsBridge.authenticatedUid?.call();

  static void _invalidateIfAccountChanged() {
    final uid = _uid;
    if (uid != _lastUid) {
      _lastUid = uid;
      _epoch++;
      notifier.value = null;
    }
  }

  static DedaVerifiedIdCardSnapshot? forIdentifier(String identifier) {
    // Build is read-only: never notify listeners during a widget build.
    final snap = notifier.value;
    if (snap == null || snap.accountUid != _uid ||
        snap.publicId != identifier || !snap.serverConfirmed ||
        (snap.activeColor != null && !snap.ownedColors.contains(snap.activeColor))) {
      return null;
    }
    return snap;
  }

  static bool _valid(DedaVerifiedIdCardSnapshot value, String uid, String id) =>
      value.serverConfirmed && value.accountUid == uid && value.publicId == id &&
      (value.activeColor == null || value.ownedColors.contains(value.activeColor));

  static Future<bool> refresh(String identifier) async {
    _invalidateIfAccountChanged();
    final uid = _uid;
    final read = DedaVerifiedIdCardsBridge.readFromServer;
    if (uid == null || uid.isEmpty || read == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(identifier)) {
      notifier.value = null;
      return false;
    }
    final epoch = ++_epoch;
    try {
      final verified = await read();
      if (epoch != _epoch || _uid != uid) return false;
      if (!_valid(verified, uid, identifier)) throw StateError('unverified-card-ownership');
      notifier.value = verified;
      return true;
    } catch (_) {
      if (epoch == _epoch) notifier.value = null;
      return false;
    }
  }

  static Future<bool> useOwned(String identifier, DedaPremiumIdCardColor color) async {
    _invalidateIfAccountChanged();
    final uid = _uid;
    final old = forIdentifier(identifier);
    final activate = DedaVerifiedIdCardsBridge.activateOnServer;
    final read = DedaVerifiedIdCardsBridge.readFromServer;
    if (uid == null || old == null || !old.ownedColors.contains(color) ||
        activate == null || read == null) return false;
    final epoch = ++_epoch;
    try {
      // Persist on trusted server first, then independently re-read ledger.
      final result = await activate(color);
      if (epoch != _epoch || _uid != uid ||
          !_valid(result, uid, identifier) || result.activeColor != color) {
        return false;
      }
      final confirmed = await read();
      if (epoch != _epoch || _uid != uid ||
          !_valid(confirmed, uid, identifier) ||
          confirmed.activeColor != color) return false;
      notifier.value = confirmed;
      return true;
    } catch (_) {
      // Preserve the old profile card on a failed or interrupted activation.
      return false;
    }
  }

  static void clearForLogout() {
    _epoch++;
    _lastUid = null;
    notifier.value = null;
  }
}

class DedaVerifiedIdCardsAccountSection extends StatefulWidget {
  final String identifier;
  const DedaVerifiedIdCardsAccountSection({
    super.key,
    required this.identifier,
  });
  @override
  State<DedaVerifiedIdCardsAccountSection> createState() =>
      _DedaVerifiedIdCardsAccountSectionState();
}

class _DedaVerifiedIdCardsAccountSectionState
    extends State<DedaVerifiedIdCardsAccountSection> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => DedaVerifiedIdCardsState.refresh(widget.identifier));
  }
  @override
  void didUpdateWidget(covariant DedaVerifiedIdCardsAccountSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      Future<void>.microtask(() => DedaVerifiedIdCardsState.refresh(widget.identifier));
    }
  }

  Future<void> _activate(DedaPremiumIdCardColor color) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await DedaVerifiedIdCardsState.useOwned(widget.identifier, color);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? dedaText('تم حفظ تصميم بطاقة الآيدي في ملفك', 'ID card style saved to profile')
          : dedaText('تعذّر تأكيد اختيار البطاقة، التصميم السابق محفوظ',
                     'Card selection not verified; previous style kept')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DedaVerifiedIdCardSnapshot?>(
      valueListenable: DedaVerifiedIdCardsState.notifier,
      builder: (context, snapshot, _) {
        final safe = DedaVerifiedIdCardsState.forIdentifier(widget.identifier);
        return DedaPremiumIdCardsManagementPanel(
          identifier: widget.identifier,
          serverVerifiedOwnedColors:
              safe?.ownedColors ?? const <DedaPremiumIdCardColor>{},
          verifiedActiveColor: safe?.activeColor,
          onActivateVerified: !_busy && safe != null &&
                  DedaVerifiedIdCardsBridge.activateOnServer != null &&
                  DedaVerifiedIdCardsBridge.readFromServer != null
              ? _activate
              : null,
          // Point12 purchase is still locked until server callables deployed.
          onPurchaseVerified: null,
          refreshVerifiedOwnership: null,
        );
      },
    );
  }
}

class DedaVerifiedIdCardsProfileSlot extends StatefulWidget {
  final String identifier;
  final VoidCallback onCopy;
  final double width;
  final bool compact;
  const DedaVerifiedIdCardsProfileSlot({
    super.key,
    required this.identifier,
    required this.onCopy,
    required this.width,
    required this.compact,
  });

  @override
  State<DedaVerifiedIdCardsProfileSlot> createState() =>
      _DedaVerifiedIdCardsProfileSlotState();
}

class _DedaVerifiedIdCardsProfileSlotState
    extends State<DedaVerifiedIdCardsProfileSlot> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => DedaVerifiedIdCardsState.refresh(widget.identifier));
  }
  @override
  void didUpdateWidget(covariant DedaVerifiedIdCardsProfileSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      Future<void>.microtask(() => DedaVerifiedIdCardsState.refresh(widget.identifier));
    }
  }
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DedaVerifiedIdCardSnapshot?>(
        valueListenable: DedaVerifiedIdCardsState.notifier,
        builder: (context, snapshot, _) => DedaProfileVerifiedIdCardSlot(
          identifier: widget.identifier,
          verifiedOwnedColor:
              DedaVerifiedIdCardsState.forIdentifier(widget.identifier)?.activeColor,
          onCopy: widget.onCopy,
          width: widget.width,
          compact: widget.compact,
        ),
      );
}

'''

def apply(source: str) -> str:
    if source.count(POINT6) != 1 or source.count(POINT12) != 1:
        raise ValueError("SAFE_STOP: protected point6 / point12 prerequisites absent")
    if source.count(ACCOUNT) != 1:
        raise ValueError("SAFE_STOP: ambiguous Account information class")
    before = original_call()
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(WIDGETS) != 1 or \
           source.count(NEW_PROFILE) != 1 or source.count(NEW_CALL) != 1:
            raise ValueError("SAFE_STOP: changed or partial point14 patch")
        return source
    if source.count(before) != 1 or source.count(OLD_PROFILE) != 1:
        raise ValueError("SAFE_STOP: original account panel / 50px profile slot differs")
    output = source.replace(before, NEW_CALL, 1).replace(OLD_PROFILE, NEW_PROFILE, 1)
    output = output.replace(ACCOUNT, WIDGETS + ACCOUNT, 1)
    if output.replace(WIDGETS, "", 1).replace(NEW_PROFILE, OLD_PROFILE, 1).replace(
        NEW_CALL, before, 1) != source:
        raise ValueError("SAFE_STOP: non-point14 changes detected")
    for forbidden in ("DedaDiamondsWallet.spend(", "DedaStyleInventory.addOwned("):
        if forbidden in WIDGETS:
            raise ValueError("SAFE_STOP: local wallet / fake card ownership forbidden")
    return output

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: reconstructed lib/main.dart not available")
    old = MAIN.read_text(encoding="utf-8")
    try:
        new = apply(old)
    except ValueError as err:
        raise SystemExit(str(err))
    if old != new:
        MAIN.write_text(new, encoding="utf-8")
    print("PASS: server-owned designs + guarded Use + 50px profile preview staged")
    print("PASS: no deployed callables, real diamonds, live Firestore, or APK")
