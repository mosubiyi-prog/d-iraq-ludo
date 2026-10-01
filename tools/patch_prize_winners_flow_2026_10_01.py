from pathlib import Path

MAIN = Path('lib/main.dart')
BACKEND = Path('lib/deda_backend.dart')
ADMIN = Path('lib/admin_pages.dart')
RULES = Path('firestore.rules')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


# --- main.dart: final card is a terminal prize stage, not a fifth claim ---
s = MAIN.read_text(encoding='utf-8')
if "import 'prize_winner_pages.dart';" not in s:
    s = replace_once(
        s,
        "import 'places_service.dart';\n",
        "import 'places_service.dart';\nimport 'prize_winner_pages.dart';\n",
        'main prize pages import',
    )

old_load = """      for (final threshold in _pointTierThresholds) {
        final reserveId = 'point_tier_reserve|$threshold';
        final claimId = 'point_tier_claim|$threshold';
        final hasReserve = awards.containsKey(reserveId);
        final hasClaim = awards.containsKey(claimId);
        if (hasReserve || hasClaim) loaded.add(threshold);
        if (hasClaim) claimed.add(threshold);
        if (!hasReserve && !hasClaim) loaded.remove(threshold);
      }

      if (migratedLegacyStageOne) {
"""
new_load = """      // Build 235 temporarily allowed the final 25,000-point card to be
      // claimed like the first four stages. The agreed prize flow keeps that
      // final reserve spent. Remove only that obsolete final claim once; the
      // 25,000 reserve remains untouched and the first four claims stay intact.
      var migratedLegacyFinalClaim = false;
      const legacyFinalClaimId = 'point_tier_claim|25000';
      if (awards.containsKey(legacyFinalClaimId)) {
        awards.remove(legacyFinalClaimId);
        ledger.removeWhere((entry) {
          if (entry is! Map) return false;
          return entry['id']?.toString() == legacyFinalClaimId;
        });
        state['awards'] = awards;
        state['ledger'] = ledger;
        await DedaTaskEngine._writeState(prefs, accountKey, state);
        migratedLegacyFinalClaim = true;
      }

      for (final threshold in _pointTierThresholds) {
        final reserveId = 'point_tier_reserve|$threshold';
        final claimId = 'point_tier_claim|$threshold';
        final hasReserve = awards.containsKey(reserveId);
        final hasClaim = awards.containsKey(claimId);
        if (hasReserve || hasClaim) loaded.add(threshold);
        if (hasClaim) claimed.add(threshold);
        if (!hasReserve && !hasClaim) loaded.remove(threshold);
      }

      if (migratedLegacyStageOne || migratedLegacyFinalClaim) {
"""
if 'legacyFinalClaimId' not in s:
    s = replace_once(s, old_load, new_load, 'migrate obsolete final claim')

old_claim_guard = """  Future<void> _claimPointTierReward(int threshold) async {
    if (!_pointTierThresholds.contains(threshold) ||
"""
new_claim_guard = """  Future<void> _claimPointTierReward(int threshold) async {
    // The fifth card is the terminal prize stage. Its 25,000 points stay spent
    // and it never enters the normal reserve-return + bonus claim path.
    if (threshold == _pointTierThresholds.last) return;
    if (!_pointTierThresholds.contains(threshold) ||
"""
if 'terminal prize stage' not in s:
    s = replace_once(s, old_claim_guard, new_claim_guard, 'block final tier claim')

old_snackbar = """            dedaText(
              'تم خصم ${_formatPointTier(threshold)} نقطة وحجزها داخل البطاقة. استلمها مع هدية $bonus نقطة.',
              '${_formatPointTier(threshold)} points were reserved in the card. Claim them with the $bonus-point bonus.',
            ),
"""
new_snackbar = """            threshold == _pointTierThresholds.last
                ? dedaText(
                    'تم خصم ${_formatPointTier(threshold)} نقطة نهائيًا لإكمال المرحلة الأخيرة. مبروك! أصبحت الجائزة جاهزة للمطالبة من إدارة DEDA.',
                    '${_formatPointTier(threshold)} points were spent to complete the final stage. Congratulations! Your prize is ready to claim from DEDA administration.',
                  )
                : dedaText(
                    'تم خصم ${_formatPointTier(threshold)} نقطة وحجزها داخل البطاقة. استلمها مع هدية $bonus نقطة.',
                    '${_formatPointTier(threshold)} points were reserved in the card. Claim them with the $bonus-point bonus.',
                  ),
"""
if 'أصبحت الجائزة جاهزة للمطالبة' not in s:
    s = replace_once(s, old_snackbar, new_snackbar, 'final open message')

final_widget_anchor = """  Widget _rewardTierBackFace({
    required int threshold,
    required int index,
  }) {
"""
final_widget = """  Widget _finalPrizeBackFace({
    required int threshold,
    required int totalPoints,
  }) {
    const gold = Color(0xFFFFD76A);
    const deep = Color(0xFF080705);
    final thresholdLabel = _formatPointTier(threshold);
    final rewardCode = _rewardCode16();

    return Column(
      key: ValueKey<String>('reward-final-$threshold'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'DEDA',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.1,
          ),
        ),
        const SizedBox(height: 5),
        const Icon(Icons.emoji_events_rounded, color: gold, size: 38),
        const SizedBox(height: 4),
        Text(
          dedaText(
            '🎉 مبروك! أكملت جميع المراحل',
            '🎉 Congratulations! All stages completed',
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            color: gold,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          dedaText('رمز الجائزة الكامل', 'Complete prize code'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xCC020914),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gold, width: 1.4),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SelectableText(
                rewardCode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.7,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          dedaText(
            'لقد حصلت على الجائزة النهائية 👏',
            'You earned the final prize 👏',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: gold,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dedaText(
            '$thresholdLabel نقطة خُصمت لإكمال المرحلة النهائية ولا تعاد إلى الرصيد.',
            '$thresholdLabel points were spent on the final stage and are not returned.',
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8.6,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: Material(
            color: deep,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DedaPrizeWinnerRequestPage(
                      isArabic: DedaLanguageState.isArabic,
                      name: DedaPreferences.userName,
                      phone: DedaPreferences.phone,
                      dedaId: _personalDedaId,
                      rewardCode: rewardCode,
                      pointsAtCompletion: totalPoints,
                    ),
                  ),
                );
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold, width: 1.2),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    dedaText(
                      'مراسلة الإدارة للمطالبة بالجائزة',
                      'Contact administration to claim prize',
                    ),
                    maxLines: 1,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 10.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: gold, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                dedaText(
                  'اكتملت الدورة • البطاقات مغلقة',
                  'Cycle completed • cards locked',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: gold,
                  fontSize: 9.4,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

""" + final_widget_anchor
if '_finalPrizeBackFace' not in s:
    s = replace_once(s, final_widget_anchor, final_widget, 'insert final prize card face')

old_card_child = """            child: opened
                ? _rewardTierBackFace(threshold: threshold, index: index)
                : _pointTierFrontFace(
"""
new_card_child = """            child: opened
                ? (index == _pointTierThresholds.length - 1
                    ? _finalPrizeBackFace(
                        threshold: threshold,
                        totalPoints: totalPoints,
                      )
                    : _rewardTierBackFace(
                        threshold: threshold,
                        index: index,
                      ))
                : _pointTierFrontFace(
"""
if 'index == _pointTierThresholds.length - 1\n                    ? _finalPrizeBackFace' not in s:
    s = replace_once(s, old_card_child, new_card_child, 'route final card to prize face')

MAIN.write_text(s, encoding='utf-8')


# --- deda_backend.dart: one idempotent prize request per DEDA account ---
b = BACKEND.read_text(encoding='utf-8')
backend_anchor = """  static String _newAdminInviteCode() {
"""
backend_methods = r'''  static String _prizeWinnerRequestIdForPhone(String phone) {
    final accountKey = accountKeyForPhone(phone);
    if (accountKey.isEmpty) throw ArgumentError('prize-account-required');
    return 'prize_v1_$accountKey';
  }

  static Stream<Map<String, dynamic>?> prizeWinnerRequestForUser(String phone) {
    final accountKey = accountKeyForPhone(phone);
    if (accountKey.isEmpty) return Stream<Map<String, dynamic>?>.value(null);
    return FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc('prize_v1_$accountKey')
        .snapshots()
        .map((snapshot) => snapshot.exists && snapshot.data() != null
            ? <String, dynamic>{'id': snapshot.id, ...snapshot.data()!}
            : null);
  }

  static Future<String> submitPrizeWinnerRequest({
    required String name,
    required String phone,
    required String dedaId,
    required String rewardCode,
    required int pointsAtCompletion,
  }) async {
    final cleanPhone = phone.trim();
    final accountKey = accountKeyForPhone(cleanPhone);
    if (accountKey.isEmpty) throw ArgumentError('prize-account-required');
    final cleanCode = rewardCode.trim();
    if (cleanCode.length != 16) throw ArgumentError('prize-code-invalid');

    final user = await _ensureOwnerSessionForAccountKey(accountKey);
    final requestId = _prizeWinnerRequestIdForPhone(cleanPhone);
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(requestId);
    final existing = await ref.get();
    if (existing.exists) return requestId;

    await ref.set(<String, dynamic>{
      'ownerUid': user.uid,
      'accountKey': accountKey,
      'name': name.trim(),
      'phone': cleanPhone,
      'dedaId': dedaId.trim(),
      'rewardCode': cleanCode,
      'pointsAtCompletion': pointsAtCompletion,
      'completedThresholds': const <int>[5000, 10000, 15000, 20000, 25000],
      'finalReservedPoints': 25000,
      'status': 'new',
      'adminMessage': '',
      'prizeDetails': '',
      'userReply': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return requestId;
  }

  static Future<void> replyToPrizeWinnerRequestFromUser({
    required String phone,
    required String message,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) throw ArgumentError('empty-prize-reply');
    final accountKey = accountKeyForPhone(phone);
    if (accountKey.isEmpty) throw ArgumentError('prize-account-required');
    final user = await _ensureOwnerSessionForAccountKey(accountKey);
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(_prizeWinnerRequestIdForPhone(phone));
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('prize-request-not-found');
    }
    if ((data['accountKey'] ?? '').toString() != accountKey ||
        (data['ownerUid'] ?? '').toString() != user.uid) {
      throw StateError('prize-request-owner-mismatch');
    }
    if ((data['status'] ?? '').toString() != 'needs_info') {
      throw StateError('prize-reply-not-requested');
    }
    await ref.update(<String, dynamic>{
      'status': 'reviewing',
      'userReply': clean,
      'userReplyAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
      prizeWinnerRequestsForAdmin() {
    return FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  static Future<void> updatePrizeWinnerRequestFromAdmin({
    required String requestId,
    required String status,
    String adminMessage = '',
    String prizeDetails = '',
  }) async {
    const allowed = <String>{
      'new',
      'reviewing',
      'needs_info',
      'approved',
      'prize_sent',
      'delivered',
      'rejected',
    };
    if (!allowed.contains(status)) throw ArgumentError('invalid-prize-status');
    final actor = await currentAdminProfile();
    if (normalizeAdminRole(actor['role']) != 'general_manager') {
      throw StateError('general-manager-required');
    }
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(requestId);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('prize-request-not-found');
    }
    final before = snapshot.data()!;
    final update = <String, dynamic>{
      'status': status,
      'adminMessage': adminMessage.trim(),
      'prizeDetails': prizeDetails.trim(),
      'adminByUid': actor['uid'].toString(),
      'adminByName': actor['displayName'].toString(),
      'adminByRole': normalizeAdminRole(actor['role']),
      'adminUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == 'prize_sent') 'prizeSentAt': FieldValue.serverTimestamp(),
      if (status == 'delivered') 'deliveredAt': FieldValue.serverTimestamp(),
    };
    await ref.update(update);
    await _writeAdminAudit(
      'prize_winner_status_changed',
      details: <String, dynamic>{
        'sourceCollection': 'prize_winner_requests',
        'sourceId': requestId,
        'targetAccountKey': before['accountKey'],
        'targetDedaId': before['dedaId'],
        'oldStatus': before['status'],
        'newStatus': status,
      },
    );
  }

'''
if 'submitPrizeWinnerRequest' not in b:
    b = replace_once(b, backend_anchor, backend_methods + backend_anchor,
                     'insert prize backend methods')
BACKEND.write_text(b, encoding='utf-8')


# --- admin_pages.dart: general-manager-only winners entry ---
a = ADMIN.read_text(encoding='utf-8')
if "import 'prize_winner_pages.dart';" not in a:
    a = replace_once(
        a,
        "import 'deda_recovery_admin.dart';\n",
        "import 'deda_recovery_admin.dart';\nimport 'prize_winner_pages.dart';\n",
        'admin prize pages import',
    )
admin_anchor = """                      if (DedaBackend.adminHasPermission(profile, 'supportRead'))
                        _dashboardCard(
"""
admin_card = """                      if (DedaBackend.normalizeAdminRole(profile['role']) ==
                          'general_manager')
                        _dashboardCard(
                          icon: Icons.emoji_events_outlined,
                          accentColor: const Color(0xFF9A7415),
                          backgroundColor: const Color(0xD9FFF6D8),
                          title: t('🏆 الرابحون معنا', '🏆 Prize winners'),
                          subtitle: t(
                            'طلبات الفوز والتدقيق وتسليم الجوائز',
                            'Prize claims, review and delivery',
                          ),
                          onTap: () => _open(
                            DedaAdminPrizeWinnersPage(isArabic: ar),
                          ),
                        ),
""" + admin_anchor
if "title: t('🏆 الرابحون معنا'" not in a:
    a = replace_once(a, admin_anchor, admin_card, 'admin prize winners card')
ADMIN.write_text(a, encoding='utf-8')


# --- Firestore: owner read/reply + general manager review; no deletion ---
r = RULES.read_text(encoding='utf-8')
rules_anchor = """    match /support_requests/{requestId} {
"""
prize_rules = r'''    // Final DEDA points-card prize request. One deterministic request is
    // allowed per account for this prize cycle. The client card flow supplies
    // the stage record; administration remains responsible for final review.
    match /prize_winner_requests/{requestId} {
      allow create: if signedIn()
        && request.resource.data.ownerUid == request.auth.uid
        && request.resource.data.accountKey is string
        && sameAccount(request.resource.data.accountKey)
        && requestId == 'prize_v1_' + request.resource.data.accountKey
        && request.resource.data.name is string
        && request.resource.data.phone is string
        && request.resource.data.dedaId is string
        && request.resource.data.dedaId.size() > 0
        && request.resource.data.rewardCode is string
        && request.resource.data.rewardCode.size() == 16
        && request.resource.data.pointsAtCompletion is int
        && request.resource.data.pointsAtCompletion >= 0
        && request.resource.data.completedThresholds == [
          5000, 10000, 15000, 20000, 25000
        ]
        && request.resource.data.finalReservedPoints == 25000
        && request.resource.data.status == 'new'
        && request.resource.data.adminMessage == ''
        && request.resource.data.prizeDetails == ''
        && request.resource.data.userReply == ''
        && request.resource.data.createdAt == request.time
        && request.resource.data.updatedAt == request.time
        && request.resource.data.keys().hasOnly([
          'ownerUid', 'accountKey', 'name', 'phone', 'dedaId',
          'rewardCode', 'pointsAtCompletion', 'completedThresholds',
          'finalReservedPoints', 'status', 'adminMessage', 'prizeDetails',
          'userReply', 'createdAt', 'updatedAt'
        ]);

      // Exact gets for a not-yet-created request are allowed to signed-in
      // users so submission can be idempotent. Existing winner records remain
      // visible only to their owner/account or to the general manager.
      allow get: if isGeneralManager()
        || (
          signedIn()
          && (
            !exists(
              /databases/$(database)/documents/prize_winner_requests/$(requestId)
            )
            || resource.data.ownerUid == request.auth.uid
            || sameAccount(resource.data.accountKey)
          )
        );
      allow list: if isGeneralManager();

      allow update: if (
          isGeneralManager()
          && request.resource.data.status in [
            'new', 'reviewing', 'needs_info', 'approved',
            'prize_sent', 'delivered', 'rejected'
          ]
          && request.resource.data.adminByUid == request.auth.uid
          && request.resource.data.adminByName is string
          && request.resource.data.adminByRole == 'general_manager'
          && request.resource.data.adminUpdatedAt == request.time
          && request.resource.data.updatedAt == request.time
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
            'status', 'adminMessage', 'prizeDetails',
            'adminByUid', 'adminByName', 'adminByRole',
            'adminUpdatedAt', 'updatedAt', 'prizeSentAt', 'deliveredAt'
          ])
        )
        || (
          signedIn()
          && resource.data.status == 'needs_info'
          && (
            resource.data.ownerUid == request.auth.uid
            || sameAccount(resource.data.accountKey)
          )
          && request.resource.data.status == 'reviewing'
          && request.resource.data.userReply is string
          && request.resource.data.userReply.size() > 0
          && request.resource.data.userReplyAt == request.time
          && request.resource.data.updatedAt == request.time
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
            'status', 'userReply', 'userReplyAt', 'updatedAt'
          ])
        );

      allow delete: if false;
    }

'''
if 'match /prize_winner_requests/{requestId}' not in r:
    r = replace_once(r, rules_anchor, prize_rules + rules_anchor,
                     'insert prize winner rules')
RULES.write_text(r, encoding='utf-8')

print('patched final prize card, backend, admin entry, and Firestore rules')
