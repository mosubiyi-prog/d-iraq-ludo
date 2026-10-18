#!/usr/bin/env python3
"""DEDA profile stage: Point 7 compact account identity card (UI ONLY).

Apply AFTER accepted 100341 reconstructed source + royal avatar patch.
This stage does NOT activate premium ID switching, register owned IDs,
touch Firebase/auth/UID/friends/location, or mutate wallet balances.
"""
from pathlib import Path

file = Path("lib/main.dart")
source = file.read_text(encoding="utf-8")
marker = "// DEDA_100342_POINT7_COMPACT_IDS_UI_ONLY"
assert marker not in source, "SAFE_STOP point7 stage already applied"
assert "DEDA_ROYAL_THREE_AVATARS_STEP1_2026_10_17" in source, \
    "SAFE_STOP stage requires final 100341 royal portrait source"

start = "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
end = "class DedaDiamondsState {"
assert source.count(start) == 1 and source.count(end) == 1, \
    "SAFE_STOP account class anchors absent"
a = source.index(start)
b = source.index(end, a)
old = source[a:b]
assert old.count("  @override\n  Widget build(BuildContext context) {") == 1, \
    "SAFE_STOP account build anchor changed"
list_anchor = "          children: [\n            Container("
assert old.count(list_anchor) == 1, \
    "SAFE_STOP account list layout changed"

new_methods = r'''
  // DEDA_100342_POINT7_COMPACT_IDS_UI_ONLY
  // A genuinely LIVE personal identifier; no fake premium ownership list.
  // The active-owned-ID backend is explicitly NOT ready for switching.

  // ID MANAGEMENT stays on Account Info, never opens the portrait/frame editor.
  // No premium activation or local ownership claim until a trusted registry is
  // available and ALL existing DEDA share-ID consumers are migrated safely.
  bool _showIdentifierManagement = false;

  void _toggleIdentifierManagement() {
    setState(() {
      _showIdentifierManagement = !_showIdentifierManagement;
    });
  }

  Widget _identifierManagementPanel(String originalId) {
    return Container(
      key: const Key('deda_point7_inline_id_manager'),
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFE6D7A2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            dedaText('إدارة المعرّفات', 'Manage identifiers'),
            style: const TextStyle(
              color: Color(0xFF775606),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            dedaText('المعرّف الأصلي المحفوظ', 'Preserved original ID'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF536577)),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              originalId,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF283C5B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            dedaText(
              'المعرّفات المميزة المملوكة: لا يمكن عرض ملكيتها أو تفعيلها قبل ربطها بسجل موثوق. لن يتغير معرّفك الحالي.',
              'Owned premium IDs require a trusted ownership registry before listing or activation. Your current ID remains unchanged.',
            ),
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF626F6B)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('deda_point7_activate_requires_verified_ownership'),
            onPressed: null,
            child: Text(dedaText('التفعيل بعد التحقق', 'Activate after verification')),
          ),
        ],
      ),
    );
  }

  Widget _ownedIdsCompactCard() {
    final originalId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    final displayId = originalId.isEmpty ? '—' : originalId;
    return Container(
      key: const Key('deda_point7_compact_owned_ids_card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8C966), width: 1.1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.badge_outlined,
                  color: Color(0xFF976A08), size: 18),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  dedaText('معرّفاتي', 'My identifiers'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF775606),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F1E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dedaText('الأصلي • فعّال', 'Original • active'),
                  style: const TextStyle(
                    color: Color(0xFF26632E),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              Flexible(
                fit: FlexFit.tight,
                child: Container(
                  key: const Key('deda_point7_current_id_chip'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: const Color(0xFFD8BE72)),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      displayId,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF283C5B),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              // Do not pretend that a locally drawn selection changes the
              // stable UID or resolves ID-based friends / location sharing.
              TextButton(
                key: const Key('deda_point7_switch_opens_id_manager'),
                onPressed: _toggleIdentifierManagement,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: const Size(54, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  dedaText('استبدال', 'Switch'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 2),
              TextButton(
                key: const Key('deda_point7_edit_identifier_action'),
                onPressed: _toggleIdentifierManagement,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: const Size(48, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  dedaText('تعديل', 'Edit'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (_showIdentifierManagement)
            _identifierManagementPanel(displayId),
        ],
      ),
    );
  }

'''
account = old.replace(
    "  @override\n  Widget build(BuildContext context) {",
    new_methods + "  @override\n  Widget build(BuildContext context) {", 1,
)
account = account.replace(
    list_anchor,
    """          children: [
            _ownedIdsCompactCard(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                dedaText(
                  'المعرّفات المميزة المملوكة تظهر بعد ربط الملكية والتحقق منها. الاستبدال متوقف لحمايتك.',
                  'Owned premium identifiers appear after verified ownership linking. Switching is disabled for safety.',
                ),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF626F6B),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Container(""", 1,
)
assert "DedaPreferences.setAccountType(type)" in account, \
    "SAFE_STOP legacy account-type update lost"
assert "DedaPreferences.phone," in account, "SAFE_STOP phone display lost"
assert "deda_point7_activate_requires_verified_ownership" in account and \
    "onPressed: null" in account, \
    "SAFE_STOP disallowed unverified premium activation"
assert "DedaEditProfilePage()" not in account, \
    "SAFE_STOP ID editor must not navigate to portraits/frames"
result = source[:a] + account + source[b:]
assert result[:a] == source[:a] and result[a + len(account):] == source[b:], \
    "SAFE_STOP non-account code change"
for guarded in ("class DedaDiamondsWallet {",
                "class DedaSocialProgressWallet {",
                "class DedaRoutePage extends StatefulWidget",
                "class DedaAccountInfoPage extends StatefulWidget"):
    assert guarded in result, "SAFE_STOP protected source section absent: " + guarded
file.write_text(result, encoding="utf-8")
print("PASS: compact real-ID point7 card added to account info; no backend writes")
print("PASS: replacement disabled until real ownership/routing verified; phone/type retained")
