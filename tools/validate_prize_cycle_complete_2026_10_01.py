from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
backend = Path('lib/deda_backend.dart').read_text(encoding='utf-8')
prize = Path('lib/prize_winner_pages.dart').read_text(encoding='utf-8')
rules = Path('firestore.rules').read_text(encoding='utf-8')
build = Path('.github/workflows/build.yml').read_text(encoding='utf-8')
deploy = Path('.github/workflows/deploy-prize-winners-firestore.yml').read_text(encoding='utf-8')

# Final points card remains terminal and now reacts to winner-confirmed delivery.
assert "status == 'delivered'" in main
assert 'انتظر الحدث القادم وشارك من جديد يا عزيزي' in main
assert 'اكتملت الدورة • البطاقات مغلقة • انتظر الحدث القادم' in main
assert 'متابعة طلب الجائزة مع الإدارة' in main
assert "if (threshold == _pointTierThresholds.last) return;" in main

# Backend: explicit cycle, admin sends, winner confirms.
assert "prizeWinnerCycleId = 'prize_v1'" in backend
assert 'confirmPrizeReceivedByUser' in backend
assert "'winnerConfirmedAt': FieldValue.serverTimestamp()" in backend
assert "'deliveredAt': FieldValue.serverTimestamp()" in backend
assert "'delivered',\n      'rejected'" not in backend
assert 'invalid-prize-status-transition' in backend
assert "'prize_sent': <String>{'prize_sent'}" in backend

# User UI: two-step receipt confirmation and closing message.
assert '✅ تم استلام الجائزة' in prize
assert 'هل تؤكد أنك استلمت جائزتك؟' in prize
assert 'نعم، تم الاستلام' in prize
assert 'تم تأكيد استلام جائزتك بنجاح' in prize
assert 'انتظر الحدث القادم وشارك من جديد يا عزيزي' in prize

# Admin UI: search + stable serials + same request history.
assert 'class _DedaAdminPrizeWinnersPageState' in prize
assert 'ابحث بالاسم أو المعرف أو الهاتف أو رقم الفائز' in prize
assert "padLeft(3, '0')" in prize
assert "t('رقم الفائز', 'Winner number')" in prize
assert '_savedStatus' in prize
assert 'بانتظار تأكيد الفائز' in prize
assert 'singleLine: true' in prize
assert 'winnerConfirmedAt' in prize

# Security: only winner/account can mark a sent prize delivered; no deletes.
assert "request.resource.data.cycleId == 'prize_v1'" in rules
assert "resource.data.status == 'prize_sent'" in rules
assert "request.resource.data.status == 'delivered'" in rules
assert 'request.resource.data.winnerConfirmedAt == request.time' in rules
assert "'status', 'winnerConfirmedAt', 'deliveredAt', 'updatedAt'" in rules
assert 'allow delete: if false;' in rules

# One test branch runs both protected validation and deployment.
assert '      - prize-cycle-complete-2026-10-01' in build
assert 'validate_prize_cycle_complete_2026_10_01.py' in build
assert '      - prize-cycle-complete-2026-10-01' in deploy
assert 'ref: ${{ github.ref_name }}' in deploy

print('complete prize cycle invariants validated')
