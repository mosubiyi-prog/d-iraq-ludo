from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
service = Path('lib/deda_social_service.dart').read_text(encoding='utf-8')
backend = Path('lib/deda_backend.dart').read_text(encoding='utf-8')
admin = Path('lib/admin_pages.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f'100270 validation failed: {label} missing: {needle}')


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise SystemExit(f'100270 validation failed: {label} still present: {needle}')

# Relationship query and Requests error handling.
require(service, '// DEDA_SOCIAL_QUERY_FIX_100270', 'social query marker')
require(service, ".where('requesterPublicId', isEqualTo: uid)", 'sent-request query')
require(service, ".where('recipientPublicId', isEqualTo: uid)", 'incoming-request query')
forbid(service, ".where('members', arrayContains: uid)", 'old ambiguous relationship query')
require(main, 'if (snapshot.hasError)', 'requests explicit stream error state')
require(main, 'تعذر قراءة طلبات الصداقة الآن', 'requests friendly query error')

# New incoming request badge: count unseen only, mark seen without changing relation status.
require(main, 'class DedaIncomingRequestNotifications', 'incoming request notification tracker')
require(main, 'unseenNotifier', 'incoming unseen counter')
require(main, 'markCurrentIncomingSeen', 'incoming request seen action')
require(main, 'deda_social_seen_incoming_v1_', 'account-scoped seen store')
require(main, "if (index == 2)", 'requests-tab badge clear hook')
# No status mutation is allowed inside markCurrentIncomingSeen.
seen_start = main.index('static Future<void> markCurrentIncomingSeen()')
seen_end = main.index('static Future<void> stop()', seen_start)
seen_scope = main[seen_start:seen_end]
forbid(seen_scope, "status", 'request-seen marker mutating friendship status')
forbid(seen_scope, "deda_friendships", 'request-seen marker writing relations')

# Appearance source is unified.
require(main, 'class DedaProfileAppearanceState', 'appearance notifier')
require(main, 'DedaProfileAppearanceState.frameNotifier.value = index;', 'style-to-profile frame sync')
require(main, 'ValueListenableBuilder<int>(\n                valueListenable: DedaProfileAppearanceState.frameNotifier', 'my-profile frame listener')
require(main, 'DedaFramedAvatar(\n                    avatarStyle: DedaPreferences.profileAvatarStyle,\n                    frameStyle: frameStyle,\n                    size: 124,', 'public preview shared frame')
forbid(main, 'colors: <Color>[_gold, Colors.white, _navy]', 'old fixed public profile ring')
require(main, 'progress.level < minLevel\n                                  ? null', 'locked frame button disabled by level')
require(main, "(_progress?.level ?? 1) < level\n                  ? null", 'locked badge button disabled by level')

# Settings logout placement and proven behavior.
require(main, '// DEDA_SETTINGS_LOGOUT_100270', 'settings logout marker')
settings_start = main.index('class _DedaSettingsPageState')
settings_end = main.index('class OwnerPlacePage', settings_start)
settings = main[settings_start:settings_end]
require(settings, 'Future<void> _logoutPersonalAccount()', 'settings logout handler')
require(settings, 'await DedaPreferences.logout();', 'existing personal logout engine')
require(settings, "dedaText('تسجيل الخروج', 'Sign out')", 'settings logout UI')
require(settings, 'if (_adminEntryVisible) ...[', 'admin section remains hidden for ordinary users')
if settings.index("dedaText('تسجيل الخروج', 'Sign out')", settings.index('if (_adminEntryVisible) ...[')) < settings.index('if (_adminEntryVisible) ...['):
    raise SystemExit('100270 validation failed: logout is not after administration section')

# General-manager diamond gift system and immutable audit.
require(backend, '// DEDA_ADMIN_DIAMONDS_100270', 'admin diamonds backend marker')
require(backend, 'generalManagerDiamondGiftBudget = 1000000', 'one-million manager pool')
require(backend, 'ensureGeneralManagerDiamondGiftWallet()', 'manager wallet initializer')
require(backend, 'grantDiamondGift({', 'manager gift transaction')
require(backend, "collection('deda_diamond_gifts')", 'immutable gift ledger write')
require(backend, 'personalGiftedDiamondBalance', 'remote gift balance read')
require(backend, 'spendPersonalGiftedDiamonds', 'owner-only gifted balance spend')
require(admin, '// DEDA_ADMIN_DIAMOND_GIFT_UI_100270', 'admin gift UI marker')
require(admin, "DedaBackend.normalizeAdminRole(profile['role']) ==\n                          'general_manager'", 'general-manager-only gift dashboard card')
require(admin, 'DedaAdminDiamondGiftPage', 'admin diamond gift page')
require(admin, 'constraints: const BoxConstraints(minHeight: 82)', 'compact manager wallet card')
require(rules, '// DEDA_SOCIAL_ADMIN_DIAMONDS_100270', 'admin diamond rules marker')
require(rules, 'match /deda_admin_diamond_wallets/{adminUid}', 'protected manager wallet rules')
require(rules, 'request.resource.data.initialBalance == 1000000', 'exact initial admin balance')
require(rules, 'request.resource.data.balance <= resource.data.balance', 'manager wallet cannot self-refill')
require(rules, 'match /deda_diamond_gift_balances/{publicId}', 'user gifted balance rules')
require(rules, 'match /deda_diamond_gifts/{giftId}', 'immutable gift ledger rules')
require(rules, 'allow update, delete: if false;', 'immutable gift log')

# Personal effective diamonds preserve rewarded-ad/local balance and augment it with remote gifts.
require(main, 'static int _localBalance = 0;', 'local earned diamond component')
require(main, 'static int _giftedBalance = 0;', 'server gifted diamond component')
require(main, 'static int get effectiveBalance => _localBalance + _giftedBalance;', 'combined personal diamond balance')
require(main, 'personalGiftedDiamondBalance(publicId)', 'gifted diamond refresh')
require(main, 'spendPersonalGiftedDiamonds(', 'gifted diamond secure spend')

# Personal social scope remains separate from place-owner logic.
require(main, 'hasApprovedPlace: false,', 'personal-only social identity')
forbidden_social_place_fields = [
    "'placeName'",
    "'approvalNumber'",
    "'linkedPlaceId'",
]
profile_start = rules.index('match /deda_social_profiles/{publicId}')
friend_start = rules.index('match /deda_friendships/{pairKey}', profile_start)
profile_rules = rules[profile_start:friend_start]
for field in forbidden_social_place_fields:
    forbid(profile_rules, field, 'place-owner field in personal social profile rules')

# Firestore query ownership must be stable personal DEDA ID based.
require(rules, '// DEDA_SOCIAL_QUERY_RULES_100270', 'relationship list query rules marker')
require(rules, 'resource.data.requesterPublicId ==', 'requester-owned query rule')
require(rules, 'resource.data.recipientPublicId ==', 'recipient-owned query rule')

print('DEDA 100270 consolidated social/admin-diamond validation passed')
