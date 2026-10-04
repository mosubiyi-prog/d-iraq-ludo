from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_SOCIAL_HUB_PHASE1_100260',
    'class DedaSocialHubPage extends StatefulWidget',
    'class _DedaSocialHubPageState extends State<DedaSocialHubPage>',
    "MaterialPageRoute(builder: (_) => const DedaSocialHubPage()),",
    "label: dedaText('ملفي', 'My profile')",
    "label: dedaText('أصدقائي', 'Friends')",
    "label: dedaText('الطلبات', 'Requests')",
    "label: dedaText('إضافة صديق', 'Add friend')",
    "label: dedaText('الزينة', 'Style')",
    'DedaAccountHubPage(),',
    'IndexedStack(',
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing social hub phase1 anchors: ' + ' | '.join(missing))

if text.count('// DEDA_SOCIAL_HUB_PHASE1_100260') != 1:
    raise SystemExit('social hub marker must appear exactly once')

if text.count('class DedaSocialHubPage extends StatefulWidget') != 1:
    raise SystemExit('DedaSocialHubPage must be defined exactly once')

social_routes = text.count(
    "MaterialPageRoute(builder: (_) => const DedaSocialHubPage()),"
)
if social_routes != 2:
    raise SystemExit(
        f'expected main Account and diamonds-success routes to enter social hub; found {social_routes}'
    )

if "MaterialPageRoute(builder: (_) => const DedaAccountHubPage())," in text:
    raise SystemExit('direct profile route remains outside the social hub')

# Phase 1 intentionally preserves the existing account/profile page and only
# wraps it as the first social tab. No friend/requests backend is added here.
for forbidden in [
    'friendRequestsCollection',
    'sendFriendRequest(',
    'acceptFriendRequest(',
    'purchaseDecoration(',
]:
    if forbidden in text:
        raise SystemExit(f'phase 1 unexpectedly contains backend implementation: {forbidden}')

print('validated DEDA social hub phase 1 for 100260')
