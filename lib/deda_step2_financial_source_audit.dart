import 'dart:convert';

import 'deda_legacy_progress_capture.dart';
import 'deda_legacy_purchase_evidence.dart';

/// An audit of ORIGINAL-phone bytes, not a source of spendable value.
/// A missing local value is UNKNOWN, never a zero balance.
enum DedaStep2LocalArchiveStatus {
  missingUnknown,
  capturedUntrusted,
  malformedUntrusted,
}

class DedaStep2FinancialSourceAudit {
  const DedaStep2FinancialSourceAudit._(this.sources);

  final Map<String, DedaStep2LocalArchiveStatus> sources;

  /// None of these independently trusted facts can be established by this
  /// local archive. They require server-side reconciliation and writer fences.
  static const independentProofRequired = <String>[
    'earned-and-spent-diamond-ledger',
    'gift-diamond-wallet-and-claims',
    'general-manager-wallet-separation',
    'level-and-xp-award-ledger',
    'daily-task-and-traffic-award-ids',
    'paid-frame-receipts-and-ownership',
    'premium-identifier-grants-and-transfers',
    'gift-inbox-and-weekly-prize-settlement',
    'legacy-100340-writer-fence',
    'server-side-pin-attempt-throttling',
  ];

  static bool _object(String raw) {
    try {
      return jsonDecode(raw) is Map;
    } on FormatException {
      return false;
    }
  }

  static DedaStep2LocalArchiveStatus _progress(String? raw) {
    if (raw == null) return DedaStep2LocalArchiveStatus.missingUnknown;
    return _object(raw)
        ? DedaStep2LocalArchiveStatus.capturedUntrusted
        : DedaStep2LocalArchiveStatus.malformedUntrusted;
  }

  static DedaStep2LocalArchiveStatus _inventory(Object? raw) {
    if (raw == null) return DedaStep2LocalArchiveStatus.missingUnknown;
    return raw is String && _object(raw)
        ? DedaStep2LocalArchiveStatus.capturedUntrusted
        : DedaStep2LocalArchiveStatus.malformedUntrusted;
  }

  static DedaStep2FinancialSourceAudit inspect({
    required DedaLegacyProgressCapture progress,
    required DedaLegacyPurchaseCapture purchase,
  }) {
    if (progress.accountKey != purchase.accountKey ||
        progress.accountKey.isEmpty || purchase.originalId.isEmpty) {
      throw const FormatException('financial-archive-cross-account');
    }
    final results = <String, DedaStep2LocalArchiveStatus>{
      for (final part in DedaLegacyProgressPart.values)
        'progress.' + part.name: _progress(progress.raw[part]),
      'purchase.inventory': _inventory(purchase.inventory),
      for (final frame in dedaLegacyPurchaseFrames)
        'purchase.' + frame: purchase.journals[frame] == null
            ? DedaStep2LocalArchiveStatus.missingUnknown
            : DedaStep2LocalArchiveStatus.capturedUntrusted,
    };
    if (results.length != 3 + 1 + dedaLegacyPurchaseFrames.length) {
      throw const FormatException('incomplete-financial-source-catalog');
    }
    return DedaStep2FinancialSourceAudit._(Map.unmodifiable(results));
  }

  List<String> get missingUnknown => List.unmodifiable([
        for (final entry in sources.entries)
          if (entry.value == DedaStep2LocalArchiveStatus.missingUnknown)
            entry.key,
      ]);

  List<String> get malformedUntrusted => List.unmodifiable([
        for (final entry in sources.entries)
          if (entry.value == DedaStep2LocalArchiveStatus.malformedUntrusted)
            entry.key,
      ]);

  bool get independentReceiptsAndBalancesVerified => false;
  bool get canSettleFinancialBalances => false;
  bool get canRestoreXpOrPoints => false;
  bool get canGrantPurchases => false;
  bool get canReplayGiftsOrLeaguePrizes => false;
  bool get allowPhoneCutover => false;
  bool get canEraseOriginalPhoneData => false;
}
