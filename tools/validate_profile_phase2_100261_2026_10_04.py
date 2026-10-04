from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_PROFILE_PHASE2_100261',
    'class DedaProfilePhase2Page extends StatefulWidget',
    'class DedaPublicProfilePreviewPage extends StatelessWidget',
    'DedaProfilePhase2Page(),',
    "dedaText('تعديل الملف', 'Edit profile')",
    "dedaText('الصور', 'Photos')",
    "dedaText('الشارات', 'Badges')",
    "dedaText('المفضلة', 'Favorites')",
    "dedaText('نشاطاتي', 'My activity')",
    "dedaText('عرض الملف العام', 'Public profile')",
    "dedaText('نبذة عني', 'About me')",
    'DedaDiamondsWallet.balanceNotifier',
    'DedaTaskEngine.totalPointsNotifier',
    'SavedPlacesPage(showFavorites: true)',
    'SavedPlacesPage(showFavorites: false)',
    'DedaEditProfilePage()',
    'DedaBackend.personalShareIdForPhone(DedaPreferences.phone)',
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('Missing 100261 profile phase2 markers: ' + ' | '.join(missing))

if text.count('// DEDA_PROFILE_PHASE2_100261') != 2:
    raise SystemExit('Expected profile phase2 marker in patch body and social child comment exactly twice')

if text.count('class DedaProfilePhase2Page extends StatefulWidget') != 1:
    raise SystemExit('DedaProfilePhase2Page must be defined exactly once')

if text.count('class DedaPublicProfilePreviewPage extends StatelessWidget') != 1:
    raise SystemExit('Public profile preview must be defined exactly once')

if '          DedaAccountHubPage(),' in text:
    raise SystemExit('Phase1 direct profile child still active in social hub')

if 'class DedaAccountHubPage extends StatefulWidget' not in text:
    raise SystemExit('Existing account hub was removed; it must remain intact for legacy/internal flows')

# Build 100261 must stay visual/profile-only. Social backend belongs to later phases.
for forbidden in [
    'friendRequestsCollection',
    'sendFriendRequest(',
    'acceptFriendRequest(',
    'purchaseDecoration(',
]:
    if forbidden in text:
        raise SystemExit(f'100261 unexpectedly added later-phase backend logic: {forbidden}')

# Do not seed mock city, birthday or membership-date data from the design reference.
for fake in ['القاهرة', '15 مارس 1995', 'عضو منذ 2023']:
    if fake in text:
        raise SystemExit(f'100261 contains forbidden mock profile data: {fake}')

print('validated DEDA profile phase 2 for build 100261')
