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
                key: const Key(
                    'deda_point7_change_id_requires_verified_registry'),
                onPressed: null,
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
                key: const Key('deda_point7_edit_profile_action'),
                onPressed: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DedaEditProfilePage(),
                    ),
                  );
                  if (changed == true && mounted) setState(() {});
                },
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
assert "onPressed: null" in account and \
    "deda_point7_change_id_requires_verified_registry" in account, \
    "SAFE_STOP disallowed unverified ID switch"
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
