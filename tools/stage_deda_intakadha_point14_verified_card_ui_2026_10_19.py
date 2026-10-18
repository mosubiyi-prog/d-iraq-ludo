#!/usr/bin/env python3
"""Stage14: owned cosmetic ID card read+activation reflected on user profile.

Requires approved stage6 ID chip, stage7 four-card management and stage12
verified checkout UI. Does NOT deploy or call live Firebase; both external
server callbacks remain null until separately approved production wiring.
"""
import ast
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAIN = Path("lib/main.dart")
STAGE6 = HERE / "stage_deda_intakadha_point6_profile_id_slot_2026_10_18.py"
STAGE7 = HERE / "stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py"
STAGE12 = HERE / "stage_deda_intakadha_point12_safe_card_checkout_2026_10_19.py"
MARKER = "// DEDA_INTAKADHA_POINT14_SERVER_VERIFIED_CARD_USE_2026_10_19"
PROFILE = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
ACCOUNT = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
POINT12 = "// DEDA_INTAKADHA_POINT12_SAFE_CARD_CHECKOUT_UI_2026_10_19"
POINT11 = "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19"
WIDGET = r'''// DEDA_INTAKADHA_POINT14_SERVER_VERIFIED_CARD_USE_2026_10_19
// Ownership and active design must be returned by the trusted callable.
// This bridge is deliberately NOT wired to any callable in this staging
// source: real accounts see no "Use" option until the backend is deployed,
// authenticated and safely validated. No client-side bought flag or wallet.
class DedaPoint14VerifiedSnapshot {
  final String identifier;
  final Set<DedaPremiumIdCardColor> owned;
  final DedaPremiumIdCardColor? active;

  DedaPoint14VerifiedSnapshot({
    required this.identifier,
    required Set<DedaPremiumIdCardColor> owned,
    required this.active,
  }) : owned = Set<DedaPremiumIdCardColor>.unmodifiable(owned);

  bool validFor(String id) =>
      identifier == id &&
      (active == null || owned.contains(active));
}

typedef DedaPoint14ReadVerified = Future<DedaPoint14VerifiedSnapshot> Function();
typedef DedaPoint14ActivateVerified =
    Future<DedaPoint14VerifiedSnapshot> Function(DedaPremiumIdCardColor color);

class DedaPoint14VerifiedBridge {
  // Stage 14 only. Both remain NULL on the real app until the audited
  // Cloud Functions and client callable wiring are approved separately.
  static DedaPoint14ReadVerified? readRemote;
  static DedaPoint14ActivateVerified? activateRemote;

  static final ValueNotifier<DedaPoint14VerifiedSnapshot?> notifier =
      ValueNotifier<DedaPoint14VerifiedSnapshot?>(null);
  static String _identity = '';
  static int _epoch = 0;

  static void _bindIdentity(String identifier) {
    if (_identity == identifier) return;
    _identity = identifier;
    _epoch++;
    notifier.value = null;
  }

  static Future<void> refresh(String identifier) async {
    _bindIdentity(identifier);
    final generation = ++_epoch;
    final gateway = readRemote;
    // Unavailable backend or unmatched account => fail closed to standard ID.
    if (gateway == null || !identifier.startsWith('@DEDA-')) {
      notifier.value = null;
      return;
    }
    try {
      final verified = await gateway();
      if (generation != _epoch || _identity != identifier) return;
      notifier.value = verified.validFor(identifier) ? verified : null;
    } catch (_) {
      if (generation == _epoch && _identity == identifier) {
        notifier.value = null;
      }
    }
  }

  static Future<bool> useOwned(String identifier, DedaPremiumIdCardColor color) async {
    _bindIdentity(identifier);
    final old = notifier.value;
    final use = activateRemote;
    if (old == null || !old.validFor(identifier) ||
        !old.owned.contains(color) || use == null || readRemote == null) {
      return false;
    }
    final generation = ++_epoch;
    try {
      final result = await use(color);
      if (generation != _epoch || _identity != identifier) return false;
      if (!result.validFor(identifier) || result.active != color ||
          !result.owned.contains(color)) {
        // Failed confirmation must not replace the last verified profile style.
        return false;
      }
      // A successful setActive response alone is not enough: re-read server.
      final verified = await readRemote!();
      if (generation != _epoch || _identity != identifier) return false;
      if (!verified.validFor(identifier) ||
          verified.active != color || !verified.owned.contains(color)) {
        // Preserve previous verified decoration until a successful refetch.
        return false;
      }
      notifier.value = verified;
      return true;
    } catch (_) {
      // Network/server failure on Use leaves old verified selection visible.
      // Account switches still clear it independently in _bindIdentity.
      return false;
    }
  }
}

// Real file screen; only verified remote record may decorate original ID.
// No modification of original identifier, name or copy callback.
class DedaPoint14VerifiedProfileSlot extends StatefulWidget {
  final String identifier;
  final VoidCallback onCopy;
  final double width;
  final bool compact;
  const DedaPoint14VerifiedProfileSlot({
    super.key,
    required this.identifier,
    required this.onCopy,
    required this.width,
    required this.compact,
  });

  @override
  State<DedaPoint14VerifiedProfileSlot> createState() =>
      _DedaPoint14VerifiedProfileSlotState();
}

class _DedaPoint14VerifiedProfileSlotState
    extends State<DedaPoint14VerifiedProfileSlot> {
  @override
  void initState() {
    super.initState();
    DedaPoint14VerifiedBridge.refresh(widget.identifier);
  }

  @override
  void didUpdateWidget(covariant DedaPoint14VerifiedProfileSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      DedaPoint14VerifiedBridge.refresh(widget.identifier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DedaPoint14VerifiedSnapshot?>(
      valueListenable: DedaPoint14VerifiedBridge.notifier,
      builder: (context, data, child) => DedaProfileVerifiedIdCardSlot(
        identifier: widget.identifier,
        verifiedOwnedColor: data != null && data.validFor(widget.identifier)
            ? data.active
            : null,
        onCopy: widget.onCopy,
        width: widget.width,
        compact: widget.compact,
      ),
    );
  }
}

// Account information screen: row ownership and "Use" come from verified
// remote state, never local previews or the existing frame inventory.
class DedaPoint14VerifiedAccountPanel extends StatefulWidget {
  final String identifier;
  const DedaPoint14VerifiedAccountPanel({
    super.key,
    required this.identifier,
  });

  @override
  State<DedaPoint14VerifiedAccountPanel> createState() =>
      _DedaPoint14VerifiedAccountPanelState();
}

class _DedaPoint14VerifiedAccountPanelState
    extends State<DedaPoint14VerifiedAccountPanel> {
  bool _using = false;

  @override
  void initState() {
    super.initState();
    DedaPoint14VerifiedBridge.refresh(widget.identifier);
  }

  @override
  void didUpdateWidget(covariant DedaPoint14VerifiedAccountPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      _using = false;
      DedaPoint14VerifiedBridge.refresh(widget.identifier);
    }
  }

  Future<void> _use(DedaPremiumIdCardColor style) async {
    if (_using) return;
    setState(() => _using = true);
    final requestedId = widget.identifier;
    final ok = await DedaPoint14VerifiedBridge.useOwned(requestedId, style);
    if (!mounted || requestedId != widget.identifier) return;
    setState(() => _using = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok
          ? dedaText('تم اعتماد البطاقة على ملفك', 'Card applied to your profile')
          : dedaText('تعذّر تأكيد التفعيل. لم يتغير ملفك.',
              'Could not verify activation; your profile is unchanged.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DedaPoint14VerifiedSnapshot?>(
      valueListenable: DedaPoint14VerifiedBridge.notifier,
      builder: (context, state, child) {
        final verified = state != null && state.validFor(widget.identifier)
            ? state
            : null;
        return DedaPremiumIdCardsManagementPanel(
          identifier: widget.identifier,
          serverVerifiedOwnedColors: verified?.owned ??
              const <DedaPremiumIdCardColor>{},
          verifiedActiveColor: verified?.active,
          onActivateVerified:
              _using || verified == null ||
                      DedaPoint14VerifiedBridge.activateRemote == null ||
                      DedaPoint14VerifiedBridge.readRemote == null
                  ? null
                  : (color) { _use(color); },
          // Point12 checkout is still CLOSED until audited production backend
          // and server-authoritative wallet migration are approved.
          onPurchaseVerified: null,
          refreshVerifiedOwnership: null,
        );
      },
    );
  }
}

'''

def extract(path, name):
    module = ast.parse(path.read_text(encoding="utf-8"))
    values = [
        node.value.value for node in module.body
        if isinstance(node, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name
                for t in node.targets)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    ]
    if len(values) != 1:
        raise ValueError("SAFE_STOP: historical stage constant changed: " + name)
    return values[0]

OLD_HERO = extract(STAGE6, "NEW_ID")
NEW_HERO = OLD_HERO.replace(
    "DedaProfileVerifiedIdCardSlot(", "DedaPoint14VerifiedProfileSlot(", 1
).replace(
    "                      // No user owns paid artwork until verified; stages 7/12/15\n"
    "                      // will supply trusted ownership and a selected style.\n"
    "                      verifiedOwnedColor: null,\n", "", 1
)
OLD_PANEL = (
    "          DedaPremiumIdCardsManagementPanel(\n"
    "            identifier: originalId,\n"
    "            // NO entitlement is inferred from the preview. Actual ownership\n"
    "            // validation and activation belong to stages 12, 14 and 15.\n"
    "            serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},\n"
    "            verifiedActiveColor: null,\n"
    + extract(STAGE12, "CALL_NEW")
    + "          ),\n"
)
NEW_PANEL = (
    "          DedaPoint14VerifiedAccountPanel(\n"
    "            identifier: originalId,\n"
    "          ),\n"
)

def apply(source):
    if source.count(PROFILE) != 1 or source.count(ACCOUNT) != 1 or \
            source.count(POINT11) != 1 or source.count(POINT12) != 1:
        raise ValueError("SAFE_STOP: profile/account and previously approved stages required")
    if MARKER in source:
        if source.count(MARKER) != 1 or WIDGET not in source or \
                source.count(NEW_HERO) != 1 or source.count(NEW_PANEL) != 1 or \
                source.count(OLD_HERO) or source.count(OLD_PANEL):
            raise ValueError("SAFE_STOP: stage14 partial or invalid implementation")
        return source
    if source.count(OLD_HERO) != 1 or source.count(OLD_PANEL) != 1:
        raise ValueError("SAFE_STOP: expected exactly one approved ID hero and account panel")
    if source.count("DedaProfileVerifiedIdCardSlot(") != 2:
        raise ValueError("SAFE_STOP: original ID widget construction changed")
    upgraded = source.replace(OLD_HERO, NEW_HERO, 1).replace(
        OLD_PANEL, NEW_PANEL, 1
    ).replace(PROFILE, WIDGET + PROFILE, 1)
    if upgraded.replace(WIDGET, "", 1).replace(
            NEW_PANEL, OLD_PANEL, 1).replace(
            NEW_HERO, OLD_HERO, 1) != source:
        raise ValueError("SAFE_STOP: stage14 changed account wallet, names or other features")
    if ("static DedaPoint14ReadVerified? readRemote;" not in WIDGET or
            "static DedaPoint14ActivateVerified? activateRemote;" not in WIDGET or
            "onPurchaseVerified: null" not in WIDGET):
        raise ValueError("SAFE_STOP: unverified live backend or purchase mistakenly enabled")
    return upgraded

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: rebuilt Flutter lib/main.dart is missing")
    src = MAIN.read_text(encoding="utf-8")
    try:
        out = apply(src)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if out != src:
        MAIN.write_text(out, encoding="utf-8")
        print("PASS: verified owned card list/Use linked to matching account, 50dp profile ID slot")
    else:
        print("PASS: stage14 already staged")
    print("PASS: no live Firebase call, no diamonds, no account ID changes; backend remains gated")
