import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_step2_recovery_guardian.dart';

/// Read-only owner-scoped continuity across account domains. A cloud snapshot
/// is evidence of the SAME account's existing data, NEVER a new payment,
/// premium entitlement, league reward or "empty means zero" migration.
const bool dedaStep2AccountDomainsReadbackEnabled = bool.fromEnvironment(
  'DEDA_STEP2_ACCOUNT_DOMAINS_READBACK', defaultValue: false);

class DedaDomainSourceHold implements Exception {
  const DedaDomainSourceHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaDomainSourceHold($reason)';
}

class DedaDomainServerRow {
  const DedaDomainServerRow(this.fields,
      {this.id = '', this.cached = false, this.pendingWrites = false});
  final String id;
  final Map<String, dynamic>? fields;
  final bool cached, pendingWrites;
}

abstract class DedaDomainSourceIo {
  Future<DedaDomainServerRow> document(String path);
  Future<List<DedaDomainServerRow>> friendships(String uid);
  Future<List<DedaDomainServerRow>> receivedGifts(String originalId);
}

class DedaFirebaseDomainSourceIo implements DedaDomainSourceIo {
  const DedaFirebaseDomainSourceIo();

  @override
  Future<DedaDomainServerRow> document(String path) async {
    final snap = await FirebaseFirestore.instance.doc(path)
        .get(const GetOptions(source: Source.server));
    return DedaDomainServerRow(snap.data(), id: snap.id,
        cached: snap.metadata.isFromCache,
        pendingWrites: snap.metadata.hasPendingWrites);
  }

  @override
  Future<List<DedaDomainServerRow>> friendships(String uid) async {
    final result = await FirebaseFirestore.instance
        .collection('deda_friendships')
        .where('members', arrayContains: uid)
        .get(const GetOptions(source: Source.server));
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
      throw const DedaDomainSourceHold('friendships-query-not-server-proven');
    }
    return result.docs.map((row) => DedaDomainServerRow(
      row.data(), id: row.id, cached: row.metadata.isFromCache,
      pendingWrites: row.metadata.hasPendingWrites)).toList();
  }

  @override
  Future<List<DedaDomainServerRow>> receivedGifts(String originalId) async {
    final result = await FirebaseFirestore.instance
        .collection('deda_diamond_gifts')
        .where('targetPublicId', isEqualTo: originalId)
        .get(const GetOptions(source: Source.server));
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
      throw const DedaDomainSourceHold('gift-inbox-query-not-server-proven');
    }
    return result.docs.map((row) => DedaDomainServerRow(
      row.data(), id: row.id, cached: row.metadata.isFromCache,
      pendingWrites: row.metadata.hasPendingWrites)).toList();
  }
}

class DedaAccountDomainContinuity {
  const DedaAccountDomainContinuity({
    required this.status,
    required this.friendRelations,
    required this.acceptedFriends,
    required this.giftReceipts,
    required this.iraqDay,
    this.weeklyPrizeReceipts = 0,
    this.weeklyPrizePending = 0,
    this.weeklyPrizeReceived = 0,
    this.existingGiftWallet,
    this.existingWeeklyXp,
    this.activeDisplayId,
  });

  /// 'verified-existing-source' means READBACK, not issuance/transfer.
  /// Missing historical evidence must NEVER be treated as a zero balance.
  final Map<String,String> status;
  final int friendRelations, acceptedFriends, giftReceipts;
  /// Weeklies already in Hadaya; never credits or claims another time.
  final int weeklyPrizeReceipts, weeklyPrizePending, weeklyPrizeReceived;
  final String iraqDay;
  final int? existingGiftWallet, existingWeeklyXp;
  final String? activeDisplayId;

  bool get fullAccountRestored => false;
  bool get canCreditDiamonds => false;
  bool get canIssueGiftOrWeeklyPrize => false;
}

class DedaStep2AccountDomainsRecoveryReadback {
  const DedaStep2AccountDomainsRecoveryReadback({
    required this.io,
    this.enabled = dedaStep2AccountDomainsReadbackEnabled,
  });
  final DedaDomainSourceIo io;
  final bool enabled;

  void _check(DedaVaultVerifiedScope scope) {
    if (!enabled) {
      throw const DedaDomainSourceHold('domain-readback-not-enabled');
    }
    scope.validate();
  }

  Future<DedaDomainServerRow> _doc(
      DedaVaultVerifiedScope scope, String path) async {
    _check(scope);
    final row = await io.document(path);
    _check(scope);
    if (row.cached || row.pendingWrites) {
      throw const DedaDomainSourceHold('uncertain-server-document');
    }
    return row;
  }

  static int _safeBalance(Object? raw, String label) {
    if (raw is! int || raw < 0 || raw > 9007199254740991) {
      throw DedaDomainSourceHold('invalid-$label');
    }
    return raw;
  }

  Future<DedaAccountDomainContinuity> inspect(
      DedaVaultVerifiedScope scope, {DateTime? nowUtc}) async {
    await scope.checkOwner();
    _check(scope);
    final uid = scope.originalUid, account = scope.accountKey,
        id = scope.originalId;
    final original = (await _doc(scope, 'deda_share_ids/$id')).fields;
    final user = (await _doc(scope, 'users/$uid')).fields;
    final profile =
        (await _doc(scope, 'deda_account_profiles/$account')).fields;
    if (original?['ownerUid'] != uid ||
        original?['publicId'] != id ||
        original?['kind'] != 'personal' || original?['active'] != true ||
        user?['accountKey'] != account ||
        user?['sharePersonalId'] != id ||
        profile?['accountKey'] != account ||
        profile?['accountType'] is! String) {
      throw const DedaDomainSourceHold('identity-source-conflict');
    }
    final statuses = <String,String>{
      'originalIdentity': 'verified-existing-source',
      'profile': 'verified-existing-source',
    };

    final social = (await _doc(scope, 'deda_social_profiles/$id')).fields;
    if (social != null &&
        (social['ownerUid'] != uid || social['publicId'] != id)) {
      throw const DedaDomainSourceHold('social-profile-owner-mismatch');
    }
    statuses['socialProfile'] = social == null
        ? 'not-backed-up-or-legacy-unknown'
        : 'verified-existing-source';

    // Friends stay keyed by the SAME UID. DO NOT recreate invitations.
    _check(scope);
    final relations = await io.friendships(uid);
    _check(scope);
    final relationIds = <String>{};
    var accepted = 0;
    for (final item in relations) {
      final data = item.fields, members = data?['members'];
      if (item.cached || item.pendingWrites || item.id.isEmpty ||
          !relationIds.add(item.id) || members is! List ||
          members.length != 2 || !members.contains(uid) ||
          members.toSet().length != 2 ||
          !members.contains(data?['requesterUid']) ||
          !members.contains(data?['recipientUid']) ||
          !['accepted','pending','rejected'].contains(data?['status'])) {
        throw const DedaDomainSourceHold('friendship-identity-conflict');
      }
      if (data?['status'] == 'accepted') accepted++;
    }
    statuses['friends'] = relations.isEmpty
        ? 'server-query-empty-legacy-unknown'
        : 'verified-existing-uid-relations';

    // Received gifts are existing receipts, not permission to credit again.
    _check(scope);
    final gifts = await io.receivedGifts(id);
    _check(scope);
    final giftIds = <String>{};
    var weeklyPrizes = 0, weeklyPending = 0, weeklyReceived = 0;
    for (final receipt in gifts) {
      final data = receipt.fields;
      if (receipt.cached || receipt.pendingWrites ||
          receipt.id.isEmpty || !giftIds.add(receipt.id) ||
          data?['targetPublicId'] != id ||
          data?['amount'] is! int || (data!['amount'] as int) <= 0) {
        throw const DedaDomainSourceHold('gift-receipt-source-conflict');
      }
      if (data['sourceType'] == 'weekly_league') {
        // Existing original worker uses one deterministic giftId per week.
        final suffix = '-' + id.substring(1);
        if (data['giftId'] != receipt.id ||
            !RegExp(r'^deda-weekly-20\d{2}-\d{2}-\d{2}-DEDA-[A-Z0-9]{6}$')
                .hasMatch(receipt.id) ||
            !receipt.id.endsWith(suffix) ||
            !const {'pending','received','claimed'}.contains(data['status']) ||
            data['createdAt'] is! Timestamp) {
          throw const DedaDomainSourceHold('weekly-prize-receipt-conflict');
        }
        weeklyPrizes++;
        if (data['status'] == 'pending') {
          weeklyPending++;
        } else {
          weeklyReceived++;
        }
      }
    }
    statuses['giftInbox'] = gifts.isEmpty
        ? 'server-query-empty-historical-gifts-unknown'
        : 'verified-existing-receipts-no-reissue';

    final wallet =
        (await _doc(scope, 'deda_diamond_gift_balances/$id')).fields;
    if (wallet != null && wallet['publicId'] != id) {
      throw const DedaDomainSourceHold('gift-wallet-identity-conflict');
    }
    final balance = wallet == null ? null :
        _safeBalance(wallet['balance'], 'existing-gift-wallet-balance');
    statuses['giftWallet'] = wallet == null
        ? 'absent-unknown-not-zero'
        : 'existing-balance-readonly-no-credit';
    statuses['earnedDiamonds'] = 'legacy-award-ledger-not-attested';

    final premium =
        (await _doc(scope, 'deda_stage71_active_identifier/$id')).fields;
    if (premium != null && (premium['originalId'] != id ||
        premium['activeId'] is! String ||
        !(RegExp(r'^@DEDA-[A-Z0-9]{4,12}$')
            .hasMatch(premium['activeId'] as String)))) {
      throw const DedaDomainSourceHold('premium-selection-identity-conflict');
    }
    statuses['premiumIdentifier'] = premium == null
        ? 'missing-selection-ownership-unknown'
        : 'verified-display-selection-ownership-unproven';

    final leagueAccount =
        (await _doc(scope, 'deda_weekly_direct_accounts/$id')).fields;
    if (leagueAccount != null &&
        (leagueAccount['publicId'] != id ||
         leagueAccount['accountKey'] != account)) {
      throw const DedaDomainSourceHold('weekly-account-identity-conflict');
    }
    final leagueControl =
        (await _doc(scope, 'deda_weekly_direct_control/active')).fields;
    int? weeklyXp;
    final week = leagueControl?['weekId'];
    if (week is String &&
        RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(week)) {
      final row = (await _doc(
          scope, 'deda_weekly_direct_weeks/$week/scores/$id')).fields;
      if (row != null) {
        if (row['weekId'] != week || row['publicId'] != id) {
          throw const DedaDomainSourceHold('weekly-score-identity-conflict');
        }
        weeklyXp = _safeBalance(row['weeklyXp'], 'weekly-score');
      }
    } else if (week != null) {
      throw const DedaDomainSourceHold('weekly-control-invalid');
    }
    statuses['weeklyPoints'] = weeklyXp == null
        ? 'no-authoritative-week-score-yet'
        : 'existing-week-score-readonly';
    statuses['weeklyPrizes'] = weeklyPrizes == 0
        ? 'historical-prize-claims-not-attested'
        : 'existing-weekly-gift-receipts-readonly-no-reissue';

    final prefs =
        (await _doc(scope, 'deda_profile_ui_migration/$account')).fields;
    if (prefs != null &&
        (prefs['accountKey'] != account ||
         prefs['originalId'] != id ||
         prefs['uid'] != uid ||
         prefs['kind'] != 'free-profile-appearance-only')) {
      throw const DedaDomainSourceHold('visual-preferences-source-conflict');
    }
    statuses['freeAppearance'] = prefs == null
        ? 'no-cloud-backup-legacy-unknown'
        : 'verified-source-existing-ui-hydration-separate';

    // The existing quiz archive is display-state only, not earned points.
    // Restore only today's Iraq-local display data; earlier quiz records
    // must be accounted for separately before full account completion.
    final iraqNow = (nowUtc ?? DateTime.now().toUtc())
        .toUtc().add(const Duration(hours: 3));
    final iraqDay = '${iraqNow.year.toString().padLeft(4,'0')}-'
        '${iraqNow.month.toString().padLeft(2,'0')}-'
        '${iraqNow.day.toString().padLeft(2,'0')}';
    final quiz = (await _doc(scope,
        'deda_quiz_ui_snapshots/$uid/days/$iraqDay')).fields;
    if (quiz != null &&
        (quiz['kind'] != 'display-only-untrusted-quiz-v1' ||
         quiz['uid'] != uid || quiz['accountKey'] != account ||
         quiz['originalId'] != id || quiz['day'] != iraqDay)) {
      throw const DedaDomainSourceHold('quiz-ui-source-owner-conflict');
    }
    statuses['quizUiToday'] = quiz == null
        ? 'no-today-snapshot-historical-quiz-unknown'
        : 'verified-source-ui-only-hydration-separate';

    // A verified social/gift/league readback cannot invent missing
    // historical task, quiz, premium ownership, local saved-place or
    // financial records. These remain explicit HOLD categories.
    statuses.addAll(const <String,String>{
      'levelPoints': 'original-ledger-guardian-worker-required',
      'dailyTasks': 'historical-claim-ledger-not-attested',
      'trafficQuestions': 'old-phone-day-by-day-backup-not-attested',
      'ownedFrames': 'purchase-proof-guardian-worker-required',
      'savedPlaces': 'unverified-local-place-source',
      'publishedPlaces': 'same-uid-published-place-worker-required',
      'allSettings': 'free-appearance-is-not-full-settings',
    });
    await scope.checkOwner();
    _check(scope);
    return DedaAccountDomainContinuity(
      status: Map<String,String>.unmodifiable(statuses),
      friendRelations: relations.length, acceptedFriends: accepted,
      giftReceipts: gifts.length, iraqDay: iraqDay,
      weeklyPrizeReceipts: weeklyPrizes,
      weeklyPrizePending: weeklyPending,
      weeklyPrizeReceived: weeklyReceived,
      existingGiftWallet: balance,
      existingWeeklyXp: weeklyXp,
      activeDisplayId: premium?['activeId'] as String?,
    );
  }
}
