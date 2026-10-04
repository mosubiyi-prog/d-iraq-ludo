from pathlib import Path

path = Path('lib/deda_backend.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_ADMIN_DIAMONDS_100270'
if marker in text:
    print('100270 admin diamond backend already applied')
    raise SystemExit(0)

anchor = '''  static bool _hasRequiredPlaceData(Map<String, dynamic> data) {\n'''
if text.count(anchor) != 1:
    raise SystemExit(f'backend insertion anchor count={text.count(anchor)}')

code = r'''  // DEDA_ADMIN_DIAMONDS_100270
  static const int generalManagerDiamondGiftBudget = 1000000;

  static String _normalizePersonalDedaId(String raw) {
    var value = raw.trim().toUpperCase().replaceAll(' ', '');
    if (value.isNotEmpty && !value.startsWith('@')) value = '@$value';
    return value;
  }

  static bool _looksLikePersonalDedaId(String value) =>
      RegExp(r'^@DEDA-[A-Z0-9]{5,12}$')
          .hasMatch(_normalizePersonalDedaId(value));

  /// Creates the protected one-million administrative gift wallet once.
  /// It is available only to a currently authenticated active general manager.
  static Future<int> ensureGeneralManagerDiamondGiftWallet() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous ||
        !await _isCurrentGeneralManagerSession(user)) {
      throw StateError('general-manager-required');
    }

    final ref = FirebaseFirestore.instance
        .collection('deda_admin_diamond_wallets')
        .doc(user.uid);
    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        transaction.set(ref, <String, dynamic>{
          'adminUid': user.uid,
          'initialBalance': generalManagerDiamondGiftBudget,
          'balance': generalManagerDiamondGiftBudget,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return generalManagerDiamondGiftBudget;
      }
      final balance =
          ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
              .clamp(0, generalManagerDiamondGiftBudget)
              .toInt();
      return balance;
    });
  }

  static Future<Map<String, dynamic>?> adminDiamondGiftTarget(
    String rawPublicId,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous ||
        !await _isCurrentGeneralManagerSession(user)) {
      throw StateError('general-manager-required');
    }
    final publicId = _normalizePersonalDedaId(rawPublicId);
    if (!_looksLikePersonalDedaId(publicId)) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('deda_share_ids')
        .doc(publicId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data['active'] != true ||
        data['kind'] != 'personal') {
      return null;
    }
    return <String, dynamic>{
      'publicId': publicId,
      'displayName': (data['displayName'] ?? 'DEDA').toString(),
    };
  }

  /// Atomically deducts the manager pool, credits the user's remote gift
  /// balance and writes an immutable audit gift record.
  static Future<Map<String, dynamic>> grantDiamondGift({
    required String targetPublicId,
    required int amount,
  }) async {
    if (amount <= 0 || amount > generalManagerDiamondGiftBudget) {
      throw ArgumentError('invalid-diamond-gift-amount');
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

    // Ensure initial 1,000,000 exists before a transaction that spends it.
    await ensureGeneralManagerDiamondGiftWallet();

    final firestore = FirebaseFirestore.instance;
    final walletRef = firestore
        .collection('deda_admin_diamond_wallets')
        .doc(user.uid);
    final recipientRef = firestore
        .collection('deda_diamond_gift_balances')
        .doc(publicId);
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

        final recipientSnapshot = await transaction.get(recipientRef);
        final currentGifted = recipientSnapshot.exists
            ? ((recipientSnapshot.data()?['balance'] as num?)?.toInt() ?? 0)
                .clamp(0, 1 << 30)
                .toInt()
            : 0;
        final nextAdmin = currentAdmin - amount;
        final nextGifted = currentGifted + amount;

        transaction.update(walletRef, <String, dynamic>{
          'balance': nextAdmin,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (recipientSnapshot.exists) {
          transaction.update(recipientRef, <String, dynamic>{
            'balance': nextGifted,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.set(recipientRef, <String, dynamic>{
            'publicId': publicId,
            'balance': nextGifted,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.set(giftRef, <String, dynamic>{
          'giftId': giftRef.id,
          'adminUid': user.uid,
          'adminName': (admin['displayName'] ?? 'DEDA Admin').toString(),
          'targetPublicId': publicId,
          'targetName': targetName,
          'amount': amount,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return <String, dynamic>{
          'giftId': giftRef.id,
          'targetPublicId': publicId,
          'targetName': targetName,
          'amount': amount,
          'adminBalance': nextAdmin,
          'recipientGiftBalance': nextGifted,
        };
      },
    );

    await _writeAdminAudit(
      'diamond_gift',
      details: <String, dynamic>{
        'giftId': result['giftId'],
        'targetPublicId': publicId,
        'targetName': targetName,
        'amount': amount,
        'adminBalanceAfter': result['adminBalance'],
      },
    );
    return result;
  }

  /// Reads the server-backed gift portion of a personal diamond balance.
  static Future<int> personalGiftedDiamondBalance(String rawPublicId) async {
    final publicId = _normalizePersonalDedaId(rawPublicId);
    if (!_looksLikePersonalDedaId(publicId)) return 0;
    final snapshot = await FirebaseFirestore.instance
        .collection('deda_diamond_gift_balances')
        .doc(publicId)
        .get();
    return ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
        .clamp(0, 1 << 30)
        .toInt();
  }

  /// The personal account may only DECREASE its own remote gift balance.
  /// Firestore rules reject any attempt by a normal user to increase it.
  static Future<int> spendPersonalGiftedDiamonds({
    required String publicId,
    required int amount,
  }) async {
    if (amount <= 0) return personalGiftedDiamondBalance(publicId);
    final normalized = _normalizePersonalDedaId(publicId);
    if (!_looksLikePersonalDedaId(normalized)) {
      throw StateError('diamond-gift-personal-id-missing');
    }
    final ref = FirebaseFirestore.instance
        .collection('deda_diamond_gift_balances')
        .doc(normalized);
    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current =
          ((snapshot.data()?['balance'] as num?)?.toInt() ?? 0)
              .clamp(0, 1 << 30)
              .toInt();
      if (current < amount) {
        throw StateError('diamond-gift-balance-insufficient');
      }
      final next = current - amount;
      transaction.update(ref, <String, dynamic>{
        'balance': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return next;
    });
  }

'''

text = text.replace(anchor, code + anchor, 1)
path.write_text(text, encoding='utf-8')
print('applied protected 100270 general-manager diamond backend')
