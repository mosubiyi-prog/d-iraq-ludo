#!/usr/bin/env python3
"""DEDA point15: account identifier management / admin grant stage (NO DEPLOY).

The original 100356 Flutter production build is reconstructed separately. This
stage applies AFTER approved point14. All authenticated cloud bridges remain
NULL until release-gate review. Public source never ships the reserved 100 list.
"""
from pathlib import Path
import ast

HERE = Path(__file__).resolve().parent
MAIN = Path("lib/main.dart")
STAGE14 = HERE / "stage_deda_intakadha_point14_verified_card_ui_2026_10_19.py"
ANCHOR = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
PREREQ = "// DEDA_INTAKADHA_POINT14_SERVER_VERIFIED_CARD_USE_2026_10_19"
MARKER = "// DEDA_INTAKADHA_POINT15_SERVER_VERIFIED_OWNED_IDENTIFIERS_2026_10_19"

def extract(path, name):
    tree = ast.parse(path.read_text(encoding="utf8"))
    values = [n.value.value for n in tree.body if isinstance(n, ast.Assign) and
              isinstance(n.value, ast.Constant) and
              any(isinstance(t, ast.Name) and t.id == name for t in n.targets)]
    if len(values) != 1:
        raise ValueError("SAFE_STOP: missing verified stage constant " + name)
    return values[0]

OLD_PANEL = extract(STAGE14, "NEW_PANEL")
NEW_PANEL = OLD_PANEL + """          const SizedBox(height: 14),
          DedaPoint15OwnedIdentifierPanel(originalId: originalId),
          const SizedBox(height: 8),
          DedaPoint15AdminReservedGrantPanel(),
"""

WIDGET = r'''// DEDA_INTAKADHA_POINT15_SERVER_VERIFIED_OWNED_IDENTIFIERS_2026_10_19
// Prototype ONLY: never infer owned names from read-only store previews,
// local preferences, gifted cosmetic frames, or an unverified purchase receipt.
// All remote callbacks are null until audited Cloud Functions authorization.
// Until global routes (friends, share, search, public profile and copy) have
// been migrated, the actual app's existing ID remains the original ID.
class DedaPoint15OwnedIdsSnapshot {
  final String accountUid;
  final String originalId;
  final String activeId;
  final List<String> ownedIds;
  final bool serverConfirmed;

  const DedaPoint15OwnedIdsSnapshot({
    required this.accountUid,
    required this.originalId,
    required this.activeId,
    required this.ownedIds,
    required this.serverConfirmed,
  });

  bool validFor(String uid, String original) =>
      serverConfirmed && uid == accountUid &&
      originalId == original && RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original) &&
      ownedIds.isNotEmpty && ownedIds.length <= 250 &&
      ownedIds.first == original &&
      ownedIds.toSet().length == ownedIds.length &&
      ownedIds.every((id) => RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(id)) &&
      ownedIds.contains(activeId);
}

class DedaPoint15OwnedIdsBridge {
  // Auth identity MUST correspond to server's authenticated current session.
  static String? Function()? verifiedUid;
  static Future<DedaPoint15OwnedIdsSnapshot> Function()? readRemote;
  static Future<DedaPoint15OwnedIdsSnapshot> Function(String identifier)?
      activateRemote;

  // Admin access is checked again on the SERVER; this flag only hides UI.
  // No reserved ID names, secrets or catalog transferred to mobile.
  static Future<bool> Function()? verifiedGeneralManagerRemote;
  static Future<bool> Function(
    String originalRecipient, String reservedId, DedaPremiumIdCardColor color,
  )? grantReservedRemote;
}

class DedaPoint15OwnedIdsState {
  static final ValueNotifier<DedaPoint15OwnedIdsSnapshot?> notifier =
      ValueNotifier<DedaPoint15OwnedIdsSnapshot?>(null);
  static String? _accountUid;
  static String? _original;
  static int _generation = 0;

  static String? get _uid => DedaPoint15OwnedIdsBridge.verifiedUid?.call();

  static void _bindAccount(String original) {
    final newUid = _uid;
    if (_accountUid == newUid && _original == original) return;
    _accountUid = newUid;
    _original = original;
    _generation++;
    notifier.value = null;
  }

  static DedaPoint15OwnedIdsSnapshot? current(String original) {
    // UI builds are read-only. Stale/other-account snapshots never display.
    final snap = notifier.value;
    final uid = _uid;
    return uid != null && snap != null && snap.validFor(uid, original) &&
        _accountUid == uid && _original == original ? snap : null;
  }

  static Future<bool> refresh(String original) async {
    _bindAccount(original);
    final uid = _uid;
    final read = DedaPoint15OwnedIdsBridge.readRemote;
    final ticket = ++_generation;
    if (uid == null || uid.isEmpty || read == null) {
      notifier.value = null;
      return false;
    }
    try {
      final checked = await read();
      if (ticket != _generation || _uid != uid) return false;
      if (!checked.validFor(uid, original)) {
        notifier.value = null;
        return false;
      }
      notifier.value = checked;
      return true;
    } catch (_) {
      if (ticket == _generation && _uid == uid) notifier.value = null;
      return false;
    }
  }

  static Future<bool> activate(String original, String wanted) async {
    _bindAccount(original);
    final before = current(original);
    final uid = _uid;
    final use = DedaPoint15OwnedIdsBridge.activateRemote;
    final read = DedaPoint15OwnedIdsBridge.readRemote;
    if (before == null || uid == null ||
        !before.ownedIds.contains(wanted) || use == null || read == null) {
      return false;
    }
    if (wanted == before.activeId) return true;
    final ticket = ++_generation;
    try {
      final serverSet = await use(wanted);
      if (ticket != _generation || _uid != uid ||
          !serverSet.validFor(uid, original) ||
          serverSet.activeId != wanted) return false;
      final confirmed = await read();
      if (ticket != _generation || _uid != uid ||
          !confirmed.validFor(uid, original) ||
          confirmed.activeId != wanted ||
          !confirmed.ownedIds.contains(wanted)) return false;
      // Commit screen state ONLY AFTER server readback.
      notifier.value = confirmed;
      return true;
    } catch (_) {
      // Previous verified profile stays visible if network or save fails.
      return false;
    }
  }

  static void clearForLogout() {
    _generation++;
    _accountUid = null;
    _original = null;
    notifier.value = null;
  }
}

class DedaPoint15OwnedIdentifierPanel extends StatefulWidget {
  final String originalId;
  const DedaPoint15OwnedIdentifierPanel({super.key, required this.originalId});
  @override
  State<DedaPoint15OwnedIdentifierPanel> createState() =>
      _DedaPoint15OwnedIdentifierPanelState();
}

class _DedaPoint15OwnedIdentifierPanelState
    extends State<DedaPoint15OwnedIdentifierPanel> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() =>
        DedaPoint15OwnedIdsState.refresh(widget.originalId));
  }

  @override
  void didUpdateWidget(covariant DedaPoint15OwnedIdentifierPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.originalId != widget.originalId) {
      _busy = false;
      Future<void>.microtask(() =>
          DedaPoint15OwnedIdsState.refresh(widget.originalId));
    }
  }

  Future<void> _activate(String id) async {
    if (_busy || DedaPoint15OwnedIdsState.current(widget.originalId) == null) {
      return;
    }
    final oldId = widget.originalId;
    final snapshot = DedaPoint15OwnedIdsState.current(oldId);
    if (snapshot == null || !snapshot.ownedIds.contains(id) ||
        snapshot.activeId == id) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('تبديل المعرّف النشط', 'Switch active identifier')),
        content: Text(dedaText(
          'تفعيل ' + id + '؟ سيبقى المعرّف الأصلي وكل معرّفاتك الأخرى محفوظة. '
          'لا يتم حذفها أو بيعها أو خصم ماسات.',
          'Activate ' + id + '? Your original and other owned IDs stay yours; '
          'no diamonds are charged.',
        )),
        actions: <Widget>[
          TextButton(
            key: const Key('deda_point15_cancel_switch'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            key: const Key('deda_point15_confirm_switch'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dedaText('تأكيد التبديل', 'Confirm switch')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || oldId != widget.originalId || _busy) return;
    setState(() => _busy = true);
    final ok = await DedaPoint15OwnedIdsState.activate(oldId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? dedaText('تم حفظ المعرّف في سجل الحساب بعد التحقق',
              'Identifier selection verified and saved')
          : dedaText('تعذّر حفظ الاختيار. المعرّف السابق محفوظ.',
              'Could not verify selection. Previous ID preserved.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DedaPoint15OwnedIdsSnapshot?>(
      valueListenable: DedaPoint15OwnedIdsState.notifier,
      builder: (context, _, child) {
        final verified = DedaPoint15OwnedIdsState.current(widget.originalId);
        final ids = verified?.ownedIds ?? <String>[widget.originalId];
        final enabled = verified != null && !_busy &&
            DedaPoint15OwnedIdsBridge.readRemote != null &&
            DedaPoint15OwnedIdsBridge.activateRemote != null;
        return Container(
          key: const Key('deda_point15_owned_identifiers_panel'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EFFB),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(dedaText('معرّفاتي المملوكة', 'My owned identifiers'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(dedaText(
                'المعرّف الأصلي محفوظ دائمًا. التبديل يحتاج تأكيد الخادم.',
                'Original ID is always retained; switching requires server verification.',
              ), style: const TextStyle(fontSize: 11)),
              for (final identifier in ids)
                ListTile(
                  dense: true,
                  key: ValueKey<String>('deda_point15_owned_' + identifier),
                  title: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(identifier, textAlign: TextAlign.left,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  subtitle: Text(identifier == widget.originalId
                      ? dedaText('المعرّف الأصلي', 'Original ID')
                      : dedaText('معرّف مملوك', 'Owned ID')),
                  trailing: verified?.activeId == identifier
                      ? Text(dedaText('مستخدم حاليًا', 'Active'),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF176542)))
                      : OutlinedButton(
                          key: ValueKey<String>('deda_point15_select_' + identifier),
                          onPressed: enabled ? () => _activate(identifier) : null,
                          child: Text(dedaText('استخدام', 'Use')),
                        ),
                ),
              if (verified == null)
                Text(dedaText(
                  'المعرّفات الإضافية تظهر بعد إثبات الملكية من الخادم.',
                  'Other IDs appear after verified server ownership.',
                ), style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

// Admin-only allocation form. Never fetches/displays owner-private first 100
// in public app; administrator manually types the exact reserved suffix.
// Final server authorization checks owner role, catalog, recipient and races.
class DedaPoint15AdminReservedGrantPanel extends StatefulWidget {
  const DedaPoint15AdminReservedGrantPanel({super.key});
  @override
  State<DedaPoint15AdminReservedGrantPanel> createState() =>
      _DedaPoint15AdminReservedGrantPanelState();
}

class _DedaPoint15AdminReservedGrantPanelState
    extends State<DedaPoint15AdminReservedGrantPanel> {
  final TextEditingController _recipient = TextEditingController();
  final TextEditingController _name = TextEditingController();
  DedaPremiumIdCardColor _color = DedaPremiumIdCardColor.gold;
  bool _allowed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_checkAccess);
  }

  Future<void> _checkAccess() async {
    final check = DedaPoint15OwnedIdsBridge.verifiedGeneralManagerRemote;
    final allowed = check == null ? false : await check().catchError((Object _) => false);
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _grant() async {
    final action = DedaPoint15OwnedIdsBridge.grantReservedRemote;
    if (!_allowed || _busy || action == null) return;
    final recipient = _recipient.text.trim().toUpperCase();
    final name = _name.text.trim().toUpperCase();
    if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(recipient) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(name)) return;
    final choice = _color;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('تأكيد منحة المدير العام', 'Confirm manager grant')),
        content: Text(dedaText(
            'منح ' + name + ' إلى صاحب ' + recipient +
            '؟ هذا المعرّف محجوز ولا يجوز بيعه أو نقله بعد المنح.',
            'Grant ' + name + ' to owner ' + recipient +
            '? This reserved ID cannot be sold or transferred later.')),
        actions: <Widget>[
          TextButton(
            key: const Key('deda_point15_cancel_grant'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            key: const Key('deda_point15_confirm_grant'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dedaText('تأكيد المنحة', 'Confirm grant')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_allowed || _busy) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await action(recipient, name, choice);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? dedaText('تم توثيق المنحة من الخادم', 'Grant confirmed by server')
          : dedaText('لم تثبت المنحة؛ لا تغيير في الملكية', 'Grant not confirmed')),
    ));
  }

  @override
  void dispose() {
    _recipient.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed || DedaPoint15OwnedIdsBridge.grantReservedRemote == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const Key('deda_point15_admin_grant_only'),
      children: <Widget>[
        Text(dedaText('منح المعرّفات المحجوزة — المدير العام فقط',
          'Reserved identifiers — general manager only')),
        TextField(
          controller: _recipient,
          key: const Key('deda_point15_recipient_input'),
          decoration: InputDecoration(labelText: dedaText('معرّف المستلم الأصلي', 'Recipient original ID')),
        ),
        TextField(
          controller: _name,
          key: const Key('deda_point15_reserved_input'),
          decoration: InputDecoration(labelText: dedaText('المعرّف المحجوز', 'Reserved ID')),
        ),
        DropdownButton<DedaPremiumIdCardColor>(
          value: _color,
          isExpanded: true,
          items: DedaPremiumIdCardColor.values.map((c) =>
              DropdownMenuItem<DedaPremiumIdCardColor>(
                value: c, child: Text(c.name),
              ),
          ).toList(),
          onChanged: _busy ? null : (c) {
            if (c != null) setState(() => _color = c);
          },
        ),
        FilledButton(
          key: const Key('deda_point15_grant_button'),
          onPressed: _busy ? null : _grant,
          child: Text(dedaText('منح المعرّف', 'Grant identifier')),
        ),
      ],
    );
  }
}

'''

def apply(source: str) -> str:
    if source.count(PREREQ) != 1 or source.count(ANCHOR) != 1:
        raise ValueError("SAFE_STOP: approved point14 / account anchors required")
    if MARKER in source:
        if source.count(MARKER) != 1 or source.count(WIDGET) != 1 or \
           source.count(NEW_PANEL) != 1:
            raise ValueError("SAFE_STOP: partial or modified point15")
        return source
    if source.count(OLD_PANEL) != 1:
        raise ValueError("SAFE_STOP: verified point14 account panel not found once")
    result = source.replace(OLD_PANEL, NEW_PANEL, 1)
    result = result.replace(ANCHOR, WIDGET + ANCHOR, 1)
    if result.replace(WIDGET, "", 1).replace(NEW_PANEL, OLD_PANEL, 1) != source:
        raise ValueError("SAFE_STOP: unauthorized source edits")
    if "grantReservedRemote;" not in WIDGET or \
       "static Future<DedaPoint15OwnedIdsSnapshot> Function()? readRemote;" not in WIDGET:
        raise ValueError("SAFE_STOP: premature payment/grant activation")
    for token in ("DedaDiamondsWallet.spend(", "SharedPreferences.getInstance(",
                  "FirebaseFirestore.instance", "FirebaseFunctions.instance"):
        if token in WIDGET: raise ValueError("SAFE_STOP: private user data boundary")
    return result

if __name__ == "__main__":
    if not MAIN.exists(): raise SystemExit("SAFE_STOP: reconstructed 100356 source absent")
    previous = MAIN.read_text(encoding="utf8")
    try: updated = apply(previous)
    except ValueError as e: raise SystemExit(str(e))
    if updated != previous: MAIN.write_text(updated, encoding="utf8")
    print("PASS: my-owned-IDs confirm Use + optional GM private grant staged, no server integration")
    print("PASS: original ID and all existing player data unchanged; no APK, no Play")
