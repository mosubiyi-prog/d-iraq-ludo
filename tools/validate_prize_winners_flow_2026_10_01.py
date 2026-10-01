from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
backend = Path('lib/deda_backend.dart').read_text(encoding='utf-8')
admin = Path('lib/admin_pages.dart').read_text(encoding='utf-8')
prize = Path('lib/prize_winner_pages.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')

# Build 235 remains the base: daily rollover + persisted previous claim stay.
assert 'return currentLocalDayId(value);' in main
assert "!awards.containsKey('point_tier_claim|$previousThreshold')" in main

# First four claims remain unchanged, while the fifth is terminal and spent.
for pair in ('5000: 50', '10000: 100', '15000: 150', '20000: 200', '25000: 250'):
    assert pair in main
assert "if (threshold == _pointTierThresholds.last) return;" in main
assert "const legacyFinalClaimId = 'point_tier_claim|25000';" in main
assert "awards.remove(legacyFinalClaimId);" in main
assert "_finalPrizeBackFace(" in main
assert "rewardCode = _rewardCode16();" in main
assert 'اكتملت الدورة • البطاقات مغلقة' in main
assert 'مراسلة الإدارة للمطالبة بالجائزة' in main
assert "'points': -threshold" in main
assert "'points': threshold + bonus" in main

# Winner request is deterministic, account-scoped and admin-reviewed.
for marker in (
    'submitPrizeWinnerRequest',
    'replyToPrizeWinnerRequestFromUser',
    'prizeWinnerRequestForUser',
    'prizeWinnerRequestsForAdmin',
    'updatePrizeWinnerRequestFromAdmin',
    "collection('prize_winner_requests')",
    "'finalReservedPoints': 25000",
):
    assert marker in backend

assert 'class DedaPrizeWinnerRequestPage' in prize
assert 'class DedaAdminPrizeWinnersPage' in prize
assert 'class DedaAdminPrizeWinnerDetailPage' in prize
assert 'الجائزة المخصصة لك' in prize
assert 'الرد على الإدارة' in prize
assert "'needs_info'" in prize and "'delivered'" in prize

# Only the general manager receives the dedicated winners administration entry.
assert "title: t('🏆 الرابحون معنا', '🏆 Prize winners')" in admin
assert "DedaAdminPrizeWinnersPage(isArabic: ar)" in admin
assert "normalizeAdminRole(profile['role']) ==\n                          'general_manager'" in admin

# Firestore protects owner read/reply and general-manager review; no deletes.
assert 'match /prize_winner_requests/{requestId}' in rules
assert "requestId == 'prize_v1_' + request.resource.data.accountKey" in rules
assert "request.resource.data.finalReservedPoints == 25000" in rules
assert "request.resource.data.completedThresholds == [" in rules
assert 'allow list: if isGeneralManager();' in rules
assert "resource.data.status == 'needs_info'" in rules
assert 'allow delete: if false;' in rules

print('prize winner flow invariants validated')
