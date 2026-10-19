import 'package:flutter/material.dart';

/// DEDA «جمال التطبيق المتكاملة» / Stage25 owner-QA PREVIEW only.
///
/// The 63 diamonds visible in a real user's screenshot show a DISPLAYED
/// profile balance. Their exact origin, storage backend and verified-to-spend
/// portion cannot be determined from the screenshot alone.
///
/// Important: display of EXISTING balances and ownership of a spendable
/// server-verified reward are separate concepts. This model never copies,
/// adds, converts, charges, or deletes either account's diamonds.
///
/// NOT IMPORTED by main.dart; never enables real purchases, AdMob SSV,
/// migrations or Firebase writes. It exists to prevent mistaken conversion
/// while the owner's ad view continues to work in released 100358.
class DedaDiamondProvenancePreview {
  final int existingProfileVisibleDiamonds;
  final String currentAccountScope;
  final String? serverAccountScope;
  final int? serverRecordedPersonalDiamonds;
  final bool serverAccountVerified;
  final bool independentlyAuditedRewardProvenance;

  const DedaDiamondProvenancePreview({
    required this.existingProfileVisibleDiamonds,
    required this.currentAccountScope,
    this.serverAccountScope,
    this.serverRecordedPersonalDiamonds,
    this.serverAccountVerified = false,
    this.independentlyAuditedRewardProvenance = false,
  });

  /// This is the current app-facing balance (e.g. a user's screenshot 63).
  /// Do not overwrite it from an asynchronous server read or replace with 0.
  int get protectedExistingDisplay =>
      existingProfileVisibleDiamonds < 0 ? 0 : existingProfileVisibleDiamonds;

  bool get hasAccountScopedServerEvidence =>
      serverAccountVerified &&
      currentAccountScope.isNotEmpty &&
      serverAccountScope == currentAccountScope &&
      serverRecordedPersonalDiamonds != null &&
      serverRecordedPersonalDiamonds! >= 0;

  /// Pure diagnostic only: this is a RECORDED backend balance, not evidence
  /// that each historic earned diamond has a provider-signed receipt.
  int? get serverRecordedReadOnly =>
      hasAccountScopedServerEvidence ? serverRecordedPersonalDiamonds : null;

  /// Historic local ad and server gift/Telegram/SSV balances may overlap.
  /// Do NOT automatically sum the two or overwrite either source.
  bool get historicalBalanceAutoMigrationAllowed => false;
  int get importedLegacyDiamonds => 0;
  int get additionalDiamondsFromRemoteSnapshot => 0;
  bool get purchaseEnabled => false;

  /// Server payout signature and origin verification must be completed and
  /// then approved through a separate owner-reviewed production release.
  bool get historicalRewardProvenanceApproved =>
      hasAccountScopedServerEvidence &&
      independentlyAuditedRewardProvenance;
}

/// Visual diagnostic for owner QA only. It is intentionally not mounted by
/// the current app and cannot start a purchase, credit or claim an ad reward.
class DedaOwnerDiamondSafetyPreview extends StatelessWidget {
  final DedaDiamondProvenancePreview snapshot;
  const DedaOwnerDiamondSafetyPreview({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minWidth: 220),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF2),
          border: Border.all(color: const Color(0xFFE6DAB1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معاينة حماية الماسات — فحص خاص',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('الرصيد الظاهر حاليًا: ${snapshot.protectedExistingDisplay} 💎'),
            const SizedBox(height: 4),
            Text(snapshot.serverRecordedReadOnly == null
                ? 'الرصيد الخادمي: غير مؤكد للحساب الحالي'
                : 'الرصيد المسجل بالخادم (للفحص): ${snapshot.serverRecordedReadOnly} 💎'),
            const SizedBox(height: 4),
            const Text('الشراء غير مفعّل — لا تحويل تلقائي أو خصم',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
