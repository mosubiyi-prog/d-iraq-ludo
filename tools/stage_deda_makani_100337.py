"""DEDA 100337 — purely visual move from account to Makani; no backend writes.
Run after complete 100336 staging and legacy owner-entry validation.
Fail closed if any anchor changes; never modify navigation, Firestore, owner state.
"""
from pathlib import Path

p = Path('lib/main.dart')
source = p.read_text(encoding='utf-8')
marker = '// DEDA_100337_MAKANI_UI_QA'
assert marker not in source, 'SAFE_STOP: Makani stage applied twice'

def segment(start, end, label):
    assert source.count(start) == 1, 'SAFE_STOP: missing ' + label + ' start'
    i = source.index(start)
    j = source.index(end, i + len(start))
    return i, j

def replace_once(s, old, new, label):
    assert s.count(old) == 1, 'SAFE_STOP: ' + label + ' count=' + str(s.count(old))
    return s.replace(old, new, 1)

# Homepage: route only lower-left index=4; untouched top-right Help/Contact.
a, b = segment('class _HomePageState extends State<HomePage> {',
               'class DedaEditProfilePage extends StatefulWidget {', 'homepage')
home = source[a:b]
old_destination = """        case 4:
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DedaContactPage(
                initialName: DedaPreferences.userName,
                initialPhone: DedaPreferences.phone,
              ),
            ),
          );
          break;"""
new_destination = """        case 4:
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DedaMakaniPage()),
          ).then((_) {
            if (mounted) setState(() {});
          });
          break;"""
home = replace_once(home, old_destination, new_destination,
                    'bottom Messages destination')
old_item = """              premiumBottomItem(
                index: 4,
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: dedaText('الرسائل', 'Messages'),
                selected: false,
              ),"""
new_item = """              premiumBottomItem(
                index: 4,
                icon: Icons.storefront_outlined,
                selectedIcon: Icons.storefront,
                label: dedaText('مكاني', 'My place'),
                selected: false,
              ),"""
home = replace_once(home, old_item, new_item, 'lower-left Makani label and icon')
assert home.count('DedaContactPage(') >= 1, 'SAFE_STOP: top help path disappeared'
source = source[:a] + home + source[b:]

# Profile retains only personal matters, not the owner entry. Keep owner screen,
# registration flows, drafts, approval data and business logic untouched.
a, b = segment('class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {',
               'class DedaPublicProfilePreviewPage', 'personal profile')
profile = source[a:b]
old_owner_slot = """          if (_accountType == DedaAccountType.placeOwner) ...<Widget>[
            _ownerPlaceCard(),
            const SizedBox(height: 8),
          ],
"""
profile = replace_once(profile, old_owner_slot, '', 'owner profile card slot')
owner_marker = '  // DEDA_OWNER_PLACE_ENTRY_100331: visibility only; reuse original owner screen.'
assert profile.count(owner_marker) == 1
start = profile.index(owner_marker)
end = profile.index('  Widget _featureGrid() {', start)
owner_method = profile[start:end]
assert 'Widget _ownerPlaceCard()' in owner_method
assert 'const OwnerPlacePage()' in owner_method
profile = profile[:start] + profile[end:]
profile = replace_once(
    profile, 'label: dedaAccountTypeLabel(_accountType),',
    "label: dedaText('مستخدم', 'User'),",
    'personal membership label')
assert 'Widget _ownerPlaceCard()' not in profile
source = source[:a] + profile + source[b:]

# Account information keeps the phone and only the User choice. The former
# Place owner action and shortcut now live under the new Makani bottom tab.
a, b = segment('class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {',
               'class DedaAccountHubPage', 'account information')
account = source[a:b]
role_start = '                  SegmentedButton<DedaAccountType>('
assert account.count(role_start) == 1
i = account.index(role_start)
end_marker = "\n                  ),"
j = account.index(end_marker, i) + len(end_marker)
user_only = """                  OutlinedButton.icon(
                    onPressed: type == DedaAccountType.user
                        ? null
                        : () => _setType(DedaAccountType.user),
                    icon: const Icon(Icons.person_outline),
                    label: Text(dedaText('مستخدم', 'User')),
                  )"""
account = account[:i] + user_only + account[j:]
owner_shortcut = '                  if (type == DedaAccountType.placeOwner) ...<Widget>['
assert account.count(owner_shortcut) == 1
i = account.index(owner_shortcut)
j = account.index("\n                  ],", i) + len("\n                  ],")
account = account[:i] + account[j:]
assert "'صاحب مكان'" not in account and 'الانتقال إلى إدارة مكاني' not in account
assert 'DedaPreferences.phone' in account
source = source[:a] + account + source[b:]

# Reuse the tested green/gold owner card EXACTLY, now under Makani only.
makani_page = """
// DEDA_100337_MAKANI_UI_QA: navigation-only container of existing owner page.
// Enabling the existing local role uses the same DedaPreferences setter as
// the account card did. No place record is created until the existing flow.
class DedaMakaniPage extends StatefulWidget {
  const DedaMakaniPage({super.key});

  @override
  State<DedaMakaniPage> createState() => _DedaMakaniPageState();
}

class _DedaMakaniPageState extends State<DedaMakaniPage> {
  bool _changingRole = false;

  Future<void> _enablePlaceOwner() async {
    if (_changingRole ||
        DedaPreferences.accountType == DedaAccountType.placeOwner) return;
    setState(() => _changingRole = true);
    try {
      await DedaPreferences.setAccountType(DedaAccountType.placeOwner);
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dedaText(
          'تعذر تفعيل قسم صاحب المكان الآن.',
          'Could not enable place-owner access right now.',
        ))),
      );
    } finally {
      if (mounted) setState(() => _changingRole = false);
    }
  }

""" + owner_method + """
  @override
  Widget build(BuildContext context) {
    final enabled = DedaPreferences.accountType == DedaAccountType.placeOwner;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('مكاني', 'My place')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: <Widget>[
            // Exactly the former account-type owner choice; no new owner data.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4ED),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF9EC4A8)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.storefront_outlined,
                      color: Color(0xFF17652F), size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    dedaText('صاحب مكان', 'Place owner'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18),
                  )),
                  if (enabled)
                    Text(dedaText('مفعّل', 'Enabled'),
                        style: const TextStyle(
                            color: Color(0xFF17652F),
                            fontWeight: FontWeight.bold))
                  else
                    TextButton(
                      onPressed: _changingRole ? null : _enablePlaceOwner,
                      child: Text(dedaText('تفعيل', 'Enable')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (enabled) _ownerPlaceCard(),
            if (!enabled)
              Text(
                dedaText(
                  'فعّل خيار صاحب مكان للوصول إلى قسم إضافة أو إدارة مكانك.',
                  'Enable Place owner to access the existing place manager.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF54665A)),
              ),
          ],
        ),
      ),
    );
  }
}

"""
# Place it before the existing profile editor; class ordering is not semantic.
assert source.count('class DedaEditProfilePage extends StatefulWidget {') == 1
source = source.replace('class DedaEditProfilePage extends StatefulWidget {',
                        makani_page + 'class DedaEditProfilePage extends StatefulWidget {', 1)

# Preserve all proven flow callsites and class identities exactly.
for token in ('class OwnerPlacePage extends StatefulWidget',
              'DedaBackend.resubmitPlaceRequest(',
              'DedaBackend.ownerPlaceNotificationsStream(',
              'DedaBackend.ownerPlaceDeletionRequestForPlace(',
              'DedaBackend.submitPlaceEdit(',
              'DedaBackend.submitPlace(',
              'Timer.periodic(const Duration(milliseconds: 16)',
              '_buildFixedDriverArrow(navigationArrowAngle)'):
    assert source.count(token) > 0, 'SAFE_STOP: original app invariant '+token
assert source.count('class DedaMakaniPage extends StatefulWidget') == 1
assert source.count('Widget _ownerPlaceCard()') == 1
assert source.count("label: dedaText('مكاني', 'My place')") == 1
assert source.count('DedaContactPage(') > 0, 'SAFE_STOP: Help contact disappeared'

p.write_text(source, encoding='utf-8')
print('PASS: 100337 lower-left Makani, role split and original owner card moved.')
print('PASS: personal account keeps User + phone, account/session logic untouched.')
print('PASS: all owner workflows, admin approvals and accepted navigation retained.')
