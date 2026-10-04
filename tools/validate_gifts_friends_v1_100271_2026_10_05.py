from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
backend = Path('lib/deda_backend.dart').read_text(encoding='utf-8')
admin = Path('lib/admin_pages.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')

errors = []

def need(text, token, label):
    if token not in text:
        errors.append(f'missing {label}: {token}')

def forbid(text, token, label):
    if token in text:
        errors.append(f'forbidden {label}: {token}')

# Friend overflow: three dots must show a menu, and removal still routes through
# the proven confirmation method rather than deleting directly.
need(main, '// DEDA_GIFTS_MAIN_UI_100271', '100271 main UI marker')
need(main, "PopupMenuButton<String>", 'friend overflow menu')
need(main, "value: 'remove'", 'friend remove menu option')
need(main, "value: 'gift_future'", 'reserved future friend gift option')
need(main, "enabled: false", 'future friend gift disabled state')
need(main, "'هل تريد إزالة هذا الحساب من أصدقائك؟'", 'friend removal confirmation')
need(main, 'await DedaSocialService.removeRelation(relation.id);', 'confirmed relation removal')

# Main navigation is My Gifts only. Social friendship Requests must remain.
need(main, "label: dedaText('هداياي', 'My gifts')", 'main My Gifts button')
need(main, 'MaterialPageRoute(builder: (_) => const DedaMyGiftsPage())', 'My Gifts route')
need(main, 'class DedaFriendRequestsPage', 'friend requests retained')
need(main, "dedaText('الطلبات', 'Requests')", 'friend Requests social tab retained')

# Gift inbox + red pending count + permanent received state.
need(main, 'class DedaGiftInbox', 'gift inbox watcher')
need(main, 'pendingNotifier', 'pending gift count notifier')
need(main, "gift['status'] ?? '').toString() == 'pending'", 'pending-only badge count')
need(main, 'class DedaMyGiftsPage', 'gift inbox page')
need(main, "dedaText('ما عندك هدايا حاليًا'", 'clear empty gifts state')
need(main, "dedaText('الحالة: بانتظار الاستلام'", 'pending gift state')
need(main, "dedaText('الحالة: تم الاستلام'", 'received gift state')
need(main, 'DedaBackend.claimDiamondGift(', 'manual gift claim')
need(main, 'await DedaDiamondsWallet.load();', 'wallet refresh after claim')

# General manager PERSONAL million: explicit separate notifier/card and style
# purchases use that personal wallet when present.
need(main, 'generalManagerPersonalNotifier', 'GM personal wallet notifier')
need(main, 'purchasableBalance', 'GM style-purchase balance selector')
need(main, 'spendGeneralManagerPersonalDiamonds(', 'GM personal spend path')
need(main, "dedaText('رصيد المدير العام الشخصي'", 'GM personal wallet profile card')
need(backend, 'deda_gm_personal_diamond_wallets', 'GM personal wallet collection')
need(backend, 'generalManagerDiamondGiftBudget', 'one-million budget constant')

# Admin grant must create a pending gift only. It must NOT credit the recipient
# gift balance during grant.
grant_start = backend.find('static Future<Map<String, dynamic>> grantDiamondGift({')
grant_end = backend.find('static List<Map<String, dynamic>> _sortedGiftMaps', grant_start)
if grant_start < 0 or grant_end < 0:
    errors.append('grantDiamondGift block bounds missing')
else:
    grant = backend[grant_start:grant_end]
    need(grant, "'status': 'pending'", 'pending gift creation')
    need(grant, "'reason': cleanReason", 'stored gift reason')
    need(grant, "collection('deda_diamond_gifts')", 'gift ledger write')
    if "collection('deda_diamond_gift_balances')" in grant:
        errors.append('grantDiamondGift still credits recipient balance directly')

# Claim must read state and atomically update BOTH the balance and gift record.
claim_start = backend.find('static Future<Map<String, dynamic>> claimDiamondGift({')
claim_end = backend.find('/// Reads the server-backed gift portion', claim_start)
if claim_start < 0 or claim_end < 0:
    errors.append('claimDiamondGift block bounds missing')
else:
    claim = backend[claim_start:claim_end]
    need(claim, "!= 'pending'", 'claim pending-state guard')
    need(claim, "'status': 'received'", 'claim received transition')
    need(claim, "'lastClaimGiftId': cleanGiftId", 'claim replay binding')
    need(claim, 'runTransaction<Map<String, dynamic>>', 'atomic claim transaction')

# Admin reason choices and readable ledger.
for reason in [
    'لحسن سلوكك داخل DEDA',
    'لتصدرك المركز الأول',
    'لفوزك في مسابقة',
    'لمساهمتك المميزة',
    'مكافأة من إدارة DEDA',
    'سبب آخر',
]:
    need(admin, reason, f'admin reason option {reason}')
need(admin, 'reason: reason,', 'reason sent to backend')
need(admin, 'watchCurrentAdminDiamondGifts()', 'admin permanent gift ledger')
need(admin, "t('سجل هدايا الإدارة'", 'admin gift history heading')

# Security rules: pending->received is tied to the same atomic balance increase,
# and the personal manager million is isolated from the admin wallet.
need(rules, '// DEDA_GIFTS_RULES_100271', '100271 rules marker')
need(rules, 'match /deda_gm_personal_diamond_wallets/{accountKey}', 'GM personal wallet rules')
need(rules, "request.resource.data.initialBalance == 1000000", 'GM personal wallet fixed seed')
need(rules, "resource.data.status == 'pending'", 'gift pending precondition')
need(rules, "request.resource.data.status == 'received'", 'gift received transition')
need(rules, 'getAfter(', 'cross-document atomic claim verification')
need(rules, 'lastClaimGiftId', 'claim replay binding in rules')
need(rules, 'allow delete: if false;', 'immutable gift/history deletion policy')

# Keep the proven 100270 admin gift wallet and rewarded-ad wallet separation.
need(backend, "collection('deda_admin_diamond_wallets')", 'admin gift wallet retained')
need(main, 'static int _localBalance = 0;', 'local rewarded wallet retained')
need(main, 'static int _giftedBalance = 0;', 'server received gift balance retained')

if errors:
    print('DEDA 100271 VALIDATION FAILED')
    for error in errors:
        print(f' - {error}')
    raise SystemExit(1)

print('DEDA 100271 gifts/friends validation passed.')
print('Validated: friend overflow safety, separate GM million, pending gifts, reasons,')
print('manual atomic claim, red pending count, permanent user/admin history, and rules coupling.')
