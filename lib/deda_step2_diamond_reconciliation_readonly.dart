import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_step2_account_domains_recovery_readback.dart';
import 'deda_step2_assets_readback.dart';
import 'deda_step2_legacy_ad_wallet_audit.dart';
import 'deda_step2_recovery_guardian.dart';

/// Stage2 / original-UID diamond reconciliation — SOURCE OBSERVATION ONLY.
/// A server wallet is a current balance, NOT an unspent sum of gross receipts.
/// Old 100340 local AdMob values are unsigned SharedPreferences bytes.
/// No code here writes balances, redeems gifts, resends awards, or trusts a
/// user-supplied number. OFF by default until real-phone/source verification.
const bool dedaStep2DiamondReconciliationReadOnlyEnabled =
    bool.fromEnvironment('DEDA_STEP2_DIAMOND_RECONCILIATION_READ_ONLY',
        defaultValue: false);

class DedaStep2DiamondHold implements Exception {
  const DedaStep2DiamondHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2DiamondHold($reason)';
}

/// A current wallet readback and immutable preexisting receipt inventory.
/// Gross received gift receipts are diagnostic ONLY: the wallet may already
/// include them and past purchases may have spent part of those amounts.
class DedaStep2DiamondReconciliation {
  const DedaStep2DiamondReconciliation({
    required this.accountKey,
    required this.originalUid,
    required this.originalId,
    required this.receivedGiftWalletBalance,
    required this.pendingGiftReceipts,
    required this.receivedGiftReceipts,
    required this.receivedGiftGross,
    required this.pendingGiftGross,
    required this.localAdWallet,
    required this.serverReceiptIds,
    required this.warnings,
  });
  final String accountKey, originalUid, originalId;
  final int? receivedGiftWalletBalance;
  final int pendingGiftReceipts, receivedGiftReceipts;
  final int receivedGiftGross, pendingGiftGross;
  final DedaStep2LegacyAdWalletObservation localAdWallet;
  final Set<String> serverReceiptIds;
  final List<String> warnings;

  // Never sum receivedGiftGross into an existing gift wallet; it is already
  // credited at claim time under the original server rule transaction.
  int get additionalGiftDiamondsToCredit => 0;
  int get importedOldPhoneAdDiamonds => 0;
  int get additionalSpendableDiamonds => 0;
  bool get hasCompleteEarnAndSpendHistory => false;
  bool get canRestoreSpendableBalance => false;
  bool get canReplayGifts => false;
  bool get canReconcileLegacy100340LocalBalance => false;
  bool get fullAccountRestored => false;
}

/// Does not create a new financial ledger or make a client restore decision.
/// Uses the same Firebase server-only domain IO already reviewed by Stage2.
class DedaStep2DiamondReconciliationReader {
  const DedaStep2DiamondReconciliationReader({
    required this.io,
    this.enabled = dedaStep2DiamondReconciliationReadOnlyEnabled,
  });
  final DedaDomainSourceIo io;
  final bool enabled;

  void _check(DedaVaultVerifiedScope scope) {
    if (!enabled) {
      throw const DedaStep2DiamondHold('diamond-reconciliation-not-enabled');
    }
    scope.validate();
  }

  static int _amount(Object? raw, String label, {bool positive = false}) {
    if (raw is! int || raw < (positive ? 1 : 0) ||
        raw > 9007199254740991) {
      throw DedaStep2DiamondHold('invalid-$label');
    }
    return raw;
  }

  Future<DedaDomainServerRow> _server(
      DedaVaultVerifiedScope scope, String path) async {
    _check(scope);
    final row = await io.document(path);
    _check(scope);
    if (row.cached || row.pendingWrites) {
      throw const DedaStep2DiamondHold('financial-document-not-server-proven');
    }
    return row;
  }

  Future<DedaStep2DiamondReconciliation> inspect({
    required DedaVaultVerifiedScope scope,
    required String? originalPhoneAdWalletRaw,
    DedaAccountDomainContinuity? domainReadback,
    DedaStep2AssetsEvidence? assetReadback,
  }) async {
    _check(scope);
    await scope.checkOwner();
    _check(scope);

    final id = scope.originalId, uid = scope.originalUid;
    final account = scope.accountKey;
    final route = (await _server(scope, 'deda_share_ids/$id')).fields;
    final owner = (await _server(scope, 'users/$uid')).fields;
    if (route?['publicId'] != id || route?['ownerUid'] != uid ||
        route?['kind'] != 'personal' || route?['active'] != true ||
        owner?['accountKey'] != account ||
        owner?['sharePersonalId'] != id) {
      throw const DedaStep2DiamondHold('diamond-owner-uid-conflict');
    }
    if (assetReadback != null &&
        (assetReadback.originalUid != uid ||
         assetReadback.originalId != id ||
         assetReadback.accountKey != account)) {
      throw const DedaStep2DiamondHold('diamond-asset-cross-account');
    }

    // Server balance is the CURRENT residual wallet, not a fresh award.
    final wallet = (await _server(
        scope, 'deda_diamond_gift_balances/$id')).fields;
    if (wallet != null && wallet['publicId'] != id) {
      throw const DedaStep2DiamondHold('gift-wallet-not-original-owner');
    }
    final int? balance = wallet == null
        ? null : _amount(wallet['balance'], 'gift-balance');
    if (domainReadback?.existingGiftWallet != null &&
        balance != domainReadback!.existingGiftWallet) {
      throw const DedaStep2DiamondHold('diamond-domain-wallet-conflict');
    }
    if (assetReadback?.receivedGiftWalletBalance != null &&
        balance != assetReadback!.receivedGiftWalletBalance) {
      throw const DedaStep2DiamondHold('diamond-assets-wallet-conflict');
    }

    _check(scope);
    final receipts = await io.receivedGifts(id);
    _check(scope);
    final ids = <String>{};
    var pendingCount = 0, receivedCount = 0;
    var pendingGross = 0, receivedGross = 0;
    for (final row in receipts) {
      _check(scope);
      final data = row.fields;
      if (row.cached || row.pendingWrites || row.id.isEmpty ||
          !ids.add(row.id) || data?['giftId'] != row.id ||
          data?['targetPublicId'] != id ||
          !const {'admin', 'weekly_league', 'telegram'}
              .contains(data?['sourceType'])) {
        throw const DedaStep2DiamondHold('duplicate-or-cross-owner-gift-receipt');
      }
      final value = _amount(data?['amount'], 'receipt-amount',
          positive: true);
      final status = data?['status'];
      // "claimed" is accepted for historical league snapshots; neither
      // "received" nor "claimed" can be re-credited on replacement phones.
      if (status == 'pending') {
        pendingCount++;
        pendingGross = _amount(pendingGross + value, 'pending-gross');
      } else if (status == 'received' || status == 'claimed') {
        receivedCount++;
        receivedGross = _amount(receivedGross + value, 'received-gross');
      } else {
        throw const DedaStep2DiamondHold('unknown-gift-status');
      }
    }
    _check(scope);
    if (domainReadback != null &&
        domainReadback.giftReceipts != receipts.length) {
      throw const DedaStep2DiamondHold('gift-receipt-list-not-consistent');
    }

    // Gross receipts CANNOT be compared to current gift balance as if
    // there were no past frame/card purchases, Telegram rewards or debits.
    // The legacy AdMob observation remains untrusted, even if its JSON parses.
    final local = DedaStep2LegacyAdWalletObservation.inspect(
        originalPhoneAdWalletRaw);
    final warnings = <String>[
      if (wallet == null) 'missing-gift-wallet-is-unknown-not-zero',
      'received-receipts-are-already-accounted-for-no-second-credit',
      'historical-spend-and-earned-ad-ledger-not-independently-proven',
      if (local.status == DedaStep2LegacyAdWalletStatus.missingUnknown)
        'legacy-ad-wallet-not-present-unknown-not-zero',
      if (local.status ==
          DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted)
        'legacy-ad-wallet-local-value-not-a-signed-receipt',
      if (local.status == DedaStep2LegacyAdWalletStatus.malformedUntrusted)
        'legacy-ad-wallet-malformed-untrusted',
    ];
    return DedaStep2DiamondReconciliation(
      accountKey: account,
      originalUid: uid,
      originalId: id,
      receivedGiftWalletBalance: balance,
      pendingGiftReceipts: pendingCount,
      receivedGiftReceipts: receivedCount,
      pendingGiftGross: pendingGross,
      receivedGiftGross: receivedGross,
      localAdWallet: local,
      serverReceiptIds: Set.unmodifiable(ids),
      warnings: List.unmodifiable(warnings),
    );
  }
}
