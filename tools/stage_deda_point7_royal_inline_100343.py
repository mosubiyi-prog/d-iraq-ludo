#!/usr/bin/env python3
"""DEDA 100343 — royal navy/gold Point7 with inline owned-ID management.

Safe, UI-only patch after 100342. No client identifier switching, no simulated
premium inventory, no Firebase writes, no wallet/auth/location changes.
Do NOT claim premium ownership before server-authoritative registry exists.
"""
from pathlib import Path

file=Path("lib/main.dart")
s=file.read_text(encoding="utf-8")
marker="// DEDA_100343_POINT7_ROYAL_INLINE_OWNED_IDS"
assert marker not in s, "SAFE_STOP: stage already applied"
assert "// DEDA_100342_POINT7_COMPACT_IDS_UI_ONLY" in s
start="class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {"
end="class DedaDiamondsState {"
assert s.count(start)==1 and s.count(end)==1
a=s.index(start)
b=s.index(end,a)
old=s[a:b]
method="  Widget _ownedIdsCompactCard() {"
ending="  @override\n  Widget build(BuildContext context) {"
assert old.count(method)==1 and old.count(ending)==1
m=old.index(method)
n=old.index(ending,m)
assert "showModalBottomSheet<void>" in old[m:n], "SAFE_STOP: pre-patch edit handler changed"
assert "deda_point7_change_id_requires_verified_registry" in old[m:n]

new_method=r'''
  // DEDA_100343_POINT7_ROYAL_INLINE_OWNED_IDS
  bool _showOwnedIds = false;

  Widget _ownedIdsCompactCard() {
    final originalId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    final displayId = originalId.isEmpty ? '—' : originalId;
    return Container(
      key: const Key('deda_point7_compact_owned_ids_card'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFF101D45), Color(0xFF25365B)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4BD63), width: 1.35),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x25111E4B), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.badge_outlined,
                  color: Color(0xFFF4D88E), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dedaText('معرّفاتي', 'My identifiers'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFFE6A6),
                    fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF234938),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dedaText('الأصلي • فعّال', 'Original • active'),
                  style: const TextStyle(color: Color(0xFFE0F6D8),
                    fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  key: const Key('deda_point7_current_id_chip'),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF304369),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFB99958)),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(displayId,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5,
                        fontWeight: FontWeight.w900, color: Color(0xFFFFE5A4)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: const Key('deda_point7_change_id_requires_verified_registry'),
                onPressed: null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(50, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(dedaText('استبدال', 'Switch'),
                  style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 2),
              TextButton(
                key: const Key('deda_point7_edit_profile_action'),
                onPressed: () => setState(() => _showOwnedIds = !_showOwnedIds),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFDE8D),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(47, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _showOwnedIds ? dedaText('إغلاق', 'Close') : dedaText('تعديل', 'Edit'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ownedIdsInlineDetails() {
    final originalId =
        DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim();
    return Container(
      key: const Key('deda_identifier_management_inline'),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF182A53),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD3AC5C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(dedaText('معرّفاتي المملوكة', 'My owned identifiers'),
            style: const TextStyle(fontSize: 14, color: Color(0xFFFFE4A6),
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF2C416C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(dedaText('المعرّف الشخصي الأصلي • فعّال',
                                 'Original personal identifier • Active'),
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800, color: Color(0xFFE1F1E0))),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(originalId.isEmpty ? '—' : originalId,
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900, color: Color(0xFFFFE4A6))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            dedaText('المعرّفات المميزة (شراء أو هدية من الإدارة)',
                     'Premium identifiers (purchased or gifted by administration)'),
            style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 12, color: Color(0xFFFFE0A0)),
          ),
          const SizedBox(height: 5),
          Text(
            dedaText(
              'عرض المعرّفات المميزة المملوكة قيد ربط سجل الملكية والتحقق منه. '
              'لن نعرض معرفات غير مؤكدة أو نفعّل الاستبدال قبل ضمان سلامة الحساب.',
              'Verified ownership is not yet connected. No unverified identifiers '
              'or switching can be displayed until account safety checks pass.',
            ),
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFD6DDEB)),
          ),
        ],
      ),
    );
  }

'''
account=old[:m]+new_method+old[n:]
old_insert="""            _ownedIdsCompactCard(),
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
"""
new_insert="""            _ownedIdsCompactCard(),
            if (_showOwnedIds) _ownedIdsInlineDetails(),
            const SizedBox(height: 9),
"""
assert account.count(old_insert)==1, "SAFE_STOP: old notice layout changed"
account=account.replace(old_insert,new_insert,1)
assert "DedaPreferences.setAccountType(type)" in account
assert "DedaPreferences.phone," in account
assert account.count("deda_identifier_management_inline")==1
assert "showModalBottomSheet<void>" not in account[m:account.index(ending,m)]
assert "onPressed: null" in account
assert "DedaBackend.personalShareIdForPhone" in account
snew=s[:a]+account+s[b:]
assert snew[:a]==s[:a] and snew[a+len(account):]==s[b:]
assert "class DedaDiamondsWallet {" in snew
assert "class DedaRoutePage extends StatefulWidget" in snew
file.write_text(snew,encoding="utf-8")
print("PASS: navy+gold compact real-ID card; inline-only expandable management")
print("PASS: no fake premium IDs, no ID switching, no Firebase/wallet/nav mutation")
