from pathlib import Path

path = Path('lib/deda_backend.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_GIFTS_BACKEND_100271'
if marker in text:
    print('100271 gifts backend already applied')
    raise SystemExit(0)

start = text.find('  static Future<Map<String, dynamic>> grantDiamondGift({')
end_marker = '  /// Reads the server-backed gift portion of a personal diamond balance.\n'
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('100270 grantDiamondGift block not found')

replacement = r'''  // DEDA_GIFTS_BACKEND_100271
  /// Atomically deducts the protected administrative pool and creates a
  /// PENDING gift. The recipient balance is intentionally untouched here.
  static Future<Map<String, dynamic>> grantDiamondGift({
    required String targetPublicId,
    required int amount,
    required String reason,
  }) async {
    if (amount <= 0 || amount > generalManagerDiamondGiftBudget) {
      throw ArgumentError('invalid-diamond-gift-amount');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 220) {
      throw ArgumentError('invalid-diamond-gift-reason');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous ||
        !await _isCurrentGeneralManagerSession(user)) {
      throw StateError('general-manager-required');
    }
    final admin = await currentAdminProfile(forceRefresh: true);
    final target = await adminDiamondGiftTarget(targetPublicId);
    if (target == null) throw StateError('diamond-gift-target-not-found');
    final publicId = target['publicId'].toString();
    final targetName = target['displayName'].toString();

    await ensureGeneralManagerDiamondGiftWallet();

    final firestore = FirebaseFirestore.instance;
    final walletRef = firestore
        .collection('deda_admin_diamond_wallets')
        .doc(user.uid);
    final giftRef = firestore.collection('deda_diamond_gifts').doc();

    final result = await firestore.runTransaction<Map<String, dynamic>>(
      (transaction) async {
        final walletSnapshot = await transaction.get(walletRef);
        if (!walletSnapshot.exists) {
          throw StateError('diamond-admin-wallet-missing');
        }
        final currentAdmin =
            ((walletSnapshot.data()?['balance'] as num?)?.toInt() ?? 0)
                .clamp(0, generalManagerDiamondGiftBudget)
                .toInt();
        if (currentAdmin < amount) {
          throw StateError('diamond-admin-balance-insufficient');
        }
        final nextAdmin = currentAdmin - amount;

        transaction.update(walletRef, <String, dynamic>{
          'balance': nextAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(giftRef, <String, dynamic>{
          'giftId': giftRef.id,
          'sourceType': 'admin',
          'adminUid': user.uid,
          'adminName': (admin['displayName'] ?? 'DEDA Admin').toString(),
          'senderLabel': 'إدارة DEDA',
          'targetPublicId': publicId,
          'targetName': targetName,
          'amount': amount,
          'reason': cleanReason,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return <String, dynamic>{
          'giftId': giftRef.id,
          'targetPublicId': publicId,
          'targetName': targetName,
          'amount': amount,
          'reason': cleanReason,
          'status': 'pending',
          'adminBalance': nextAdmin,
        };
      },
    );

    await _writeAdminAudit(
      'diamond_gift_created',
      details: <String, dynamic>{
        'giftId': result['giftId'],
        'targetPublicId': publicId,
        'targetName': targetName,
        'amount': amount,
        'reason': cleanReason,
        'status': 'pending',
        'adminBalanceAfter': result['adminBalance'],
      },
    );
    return result;
  }

  static List<Map<String, dynamic>> _sortedGiftMaps(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items = snapshot.docs
        .map((doc) => <String, dynamic>{...doc.data(), 'giftId': doc.id})
        .toList();
    items.sort((a, b) {
      final av = a['createdAt'];
      final bv = b['createdAt'];
      final am = av is Timestamp ? av.toDate().millisecondsSinceEpoch : 0;
      final bm = bv is Timestamp ? bv.toDate().millisecondsSinceEpoch : 0;
      return bm.compareTo(am);
    });
    return items;
  }

  static Stream<List<Map<String, dynamic>>> watchPersonalDiamondGifts(
    String rawPublicId,
  ) {
    final publicId = _normalizePersonalDedaId(rawPublicId);
    if (!_looksLikePersonalDedaId(publicId)) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }
    return FirebaseFirestore.instance
        .collection('deda_diamond_gifts')
        .where('targetPublicId', isEqualTo: publicId)
        .snapshots()
        .map(_sortedGiftMaps);
  }

  static Stream<List<Map<String, dynamic>>> watchCurrentAdminDiamondGifts() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }
    return FirebaseFirestore.instance
        .collection('deda_diamond_gifts')
        .where('adminUid', isEqualTo: user.uid)
        .snapshots()
        .map(_sortedGiftMaps);
  }

  /// Claims exactly one pending gift. The gift state transition and the remote
  /// spendable balance increase are committed in the SAME transaction.
  static Future<Map<String, dynamic>> claimDiamondGift({
    required String giftId,
    required String targetPublicId,
  }) async {
    final cleanGiftId = giftId.trim();
    final publicId = _normalizePersonalDedaId(targetPublicId);
    if (cleanGiftId.isEmpty || !_looksLikePersonalDedaId(publicId)) {
      throw ArgumentError('invalid-diamond-gift-claim');
    }
    final firestore = FirebaseFirestore.instance;
    final giftRef = firestore.collection('deda_diamond_gifts').doc(cleanGiftId);
    final balanceRef = firestore
        .collection('deda_diamond_gift_balances')
        .doc(publicId);

    final result = await firestore.runTransaction<Map<String, dynamic>>(
      (transaction) async {
        final giftSnapshot = await transaction.get(giftRef);
        if (!giftSnapshot.exists || giftSnapshot.data() == null) {
          throw StateError('diamond-gift-not-found');
        }
        final gift = giftSnapshot.data()!;
        if ((gift['targetPublicId'] ?? '').toString() != publicId) {
          throw StateError('diamond-gift-not-owner');
        }
        if ((gift['status'] ?? '').toString() != 'pending') {
          throw StateError('diamond-gift-already-claimed');
        }
        final amount = ((gift['amount'] as num?)?.toInt() ?? 0);
        if (amount <= 0) throw StateError('diamond-gift-invalid-amount');

        final balanceSnapshot = await transaction.get(balanceRef);
        final current = balanceSnapshot.exists
            ? ((balanceSnapshot.data()?['balance'] as num?)?.toInt() ?? 0)
                .clamp(0, 1 << 30)
                .toInt()
            : 0;
        final next = current + amount;

        if (balanceSnapshot.exists) {
          transaction.update(balanceRef, <String, dynamic>{
            'balance': next,
            'lastClaimGiftId': cleanGiftId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(balanceRef, <String, dynamic>{
            'publicId': publicId,
            'balance': next,
            'lastClaimGiftId': cleanGiftId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.update(giftRef, <String, dynamic>{
          'status': 'received',
          'claimedAt': FieldValue.serverTimestamp(),
        });
        return <String, dynamic>{
          'giftId': cleanGiftId,
          'amount': amount,
          'balance': next,
          'status': 'received',
        };
      },
    );
    return result;
  }

'''

text = text[:start] + replacement + text[end:]

insert_anchor = '  static bool _hasRequiredPlaceData(Map<String, dynamic> data) {\n'
if text.count(insert_anchor) != 1:
    raise SystemExit('backend insertion anchor for personal GM wallet missing')

personal_wallet_code = r'''  /// Personal testing diamonds for an authorized general-manager gateway
  /// account. This wallet is separate from the administrative gift pool.
  /// Unauthorized personal accounts receive null and are not modified.
  static Future<int?> ensureGeneralManagerPersonalDiamondWallet({
    required String phone,
  }) async {
    if (!isReady) return null;
    final accountKey = accountKeyForPhone(phone).trim();
    final user = FirebaseAuth.instance.currentUser;
    if (accountKey.isEmpty || user == null || !user.isAnonymous) return null;
    final ref = FirebaseFirestore.instance
        .collection('deda_gm_personal_diamond_wallets')
        .doc(accountKey);
    try {
      return await FirebaseFirestore.instance.runTransaction<int>(
        (transaction) async {
          final snapshot = await transaction.get(ref);
          if (snapshot.exists) {
            return ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
                .clamp(0, generalManagerDiamondGiftBudget)
                .toInt();
          }
          transaction.set(ref, <String, dynamic>{
            'accountKey': accountKey,
            'initialBalance': generalManagerDiamondGiftBudget,
            'balance': generalManagerDiamondGiftBudget,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return generalManagerDiamondGiftBudget;
        },
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  static Future<int> spendGeneralManagerPersonalDiamonds({
    required String phone,
    required int amount,
  }) async {
    if (amount <= 0) return 0;
    final accountKey = accountKeyForPhone(phone).trim();
    if (accountKey.isEmpty) throw StateError('gm-personal-account-missing');
    final ref = FirebaseFirestore.instance
        .collection('deda_gm_personal_diamond_wallets')
        .doc(accountKey);
    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('gm-personal-wallet-missing');
      final current = ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
          .clamp(0, generalManagerDiamondGiftBudget)
          .toInt();
      if (current < amount) throw StateError('gm-personal-balance-insufficient');
      final next = current - amount;
      transaction.update(ref, <String, dynamic>{
        'balance': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return next;
    });
  }

'''
text = text.replace(insert_anchor, personal_wallet_code + insert_anchor, 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA 100271 pending gift backend + personal GM wallet')
