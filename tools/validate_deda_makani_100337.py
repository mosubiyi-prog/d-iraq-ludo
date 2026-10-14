"""Read-only guard of the rebuilt 100337 Makani UI; no user data is touched."""
from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
bar = Path('lib/deda_place_engagement_bar.dart').read_text(encoding='utf-8')
assert main.count('// DEDA_100337_MAKANI_UI_QA') == 1
start = main.index('class _HomePageState extends State<HomePage> {')
end = main.index('class DedaEditProfilePage extends StatefulWidget {', start)
home = main[start:end]
assert home.count("label: dedaText('مكاني', 'My place')") == 1
assert home.count("label: dedaText('الرسائل', 'Messages')") == 0
assert home.count('builder: (_) => const DedaMakaniPage()') == 1
assert home.count('DedaContactPage(') == 1, 'top-right help must remain'
assert home.count("label: dedaText('حسابي', 'Account')") == 1

a = main.index('class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {')
b = main.index('class DedaPublicProfilePreviewPage', a)
profile = main[a:b]
assert '_ownerPlaceCard()' not in profile
assert "label: dedaText('مستخدم', 'User')" in profile
assert "label: dedaAccountTypeLabel(_accountType)" not in profile

a = main.index('class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {')
b = main.index('class DedaAccountHubPage', a)
account = main[a:b]
assert 'DedaPreferences.phone' in account
assert 'DedaPreferences.setAccountType(type)' in account
assert "label: Text(dedaText('مستخدم', 'User'))" in account
assert "'صاحب مكان'" not in account
assert 'الانتقال إلى إدارة مكاني' not in account

a = main.index('class _DedaMakaniPageState extends State<DedaMakaniPage> {')
b = main.index('class DedaEditProfilePage extends StatefulWidget {', a)
makani = main[a:b]
assert makani.count("dedaText('صاحب مكان', 'Place owner')") == 1
assert makani.count('DedaPreferences.setAccountType(DedaAccountType.placeOwner)') == 1
assert 'Widget _ownerPlaceCard()' in makani
assert 'const OwnerPlacePage()' in makani
assert 'bool _changingRole = false' in makani

assert 'width: 20,' in bar
assert 'alignment: Alignment.centerRight' in bar
assert 'BoxFit.scaleDown' in bar
assert 'Color(0xFFE53935)' in bar
assert 'Color(0xFFB8860B)' in bar
assert 'Color(0xFF1877D2)' in bar
for token in ('_buildFixedDriverArrow(navigationArrowAngle)',
              'Timer.periodic(const Duration(milliseconds: 16)',
              'DedaBackend.submitPlace(',
              'DedaBackend.submitPlaceEdit(',
              'DedaBackend.resubmitPlaceRequest(',
              'DedaBackend.ownerPlaceNotificationsStream(',
              'DedaBackend.ownerPlaceDeletionRequestForPlace('):
    assert token in main, 'SAFE_STOP legacy feature missing: '+token
print('PASS: only lower-left Messages link becomes Makani; top-right support retained')
print('PASS: account info User + phone, existing owner card moved, same owner screen')
print('PASS: likes closer to red heart, follower/like actions and navigation unchanged')
