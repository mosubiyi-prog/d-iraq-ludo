import 'dart:convert';

/// OLD 100340 AdMob client wrote exactly balance/viewsToday/day locally.
/// A JSON shape match can help detect corruption but CANNOT demonstrate an
/// authentic rewarded ad, redemption, purchase, or a server-acknowledged spend.
enum DedaStep2LegacyAdWalletStatus {
  missingUnknown,
  structurallyPlausibleUntrusted,
  malformedUntrusted,
}

class DedaStep2LegacyAdWalletObservation {
  const DedaStep2LegacyAdWalletObservation._({
    required this.status,
    this.untrustedBalance,
    this.untrustedViewsToday,
    this.untrustedDay,
  });

  final DedaStep2LegacyAdWalletStatus status;
  /// Display-only historical raw number; NEVER sum into gift wallet.
  final int? untrustedBalance, untrustedViewsToday;
  final String? untrustedDay;

  static DedaStep2LegacyAdWalletObservation inspect(String? raw) {
    if (raw == null) {
      return const DedaStep2LegacyAdWalletObservation._(
        status: DedaStep2LegacyAdWalletStatus.missingUnknown);
    }
    // Preserve the original bytes upstream, including malformed/oversized.
    // The parser intentionally neither repairs nor clamps old data.
    if (raw.length > 30000 || raw.isEmpty) return _malformed();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded.length != 3 ||
          !decoded.containsKey('balance') ||
          !decoded.containsKey('viewsToday') ||
          !decoded.containsKey('day')) {
        return _malformed();
      }
      final balance = decoded['balance'];
      final views = decoded['viewsToday'];
      final day = decoded['day'];
      // Old writer used integer diamonds, 3 gems/view, max 5 views/day.
      // Neither balance % 3 nor daily views prove payment authenticity:
      // previous purchases/other sources could have changed the balance.
      if (balance is! int || balance < 0 || balance > (1 << 30) ||
          views is! int || views < 0 || views > 5 ||
          day is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(day)) {
        return _malformed();
      }
      final year = int.parse(day.substring(0,4));
      final month = int.parse(day.substring(5,7));
      final date = int.parse(day.substring(8,10));
      final actual = DateTime.utc(year,month,date);
      if (actual.year != year || actual.month != month ||
          actual.day != date) {
        return _malformed();
      }
      return DedaStep2LegacyAdWalletObservation._(
        status:DedaStep2LegacyAdWalletStatus.structurallyPlausibleUntrusted,
        untrustedBalance:balance,
        untrustedViewsToday:views,
        untrustedDay:day,
      );
    } on FormatException {
      return _malformed();
    } on TypeError {
      return _malformed();
    }
  }

  static DedaStep2LegacyAdWalletObservation _malformed() =>
      const DedaStep2LegacyAdWalletObservation._(
        status:DedaStep2LegacyAdWalletStatus.malformedUntrusted);

  /// A phone's raw preferences never authorize a real wallet transaction.
  bool get hasProviderSignedRewardReceipts => false;
  bool get hasServerSpendLedger => false;
  bool get canReconcileSpendableDiamondBalance => false;
  bool get canReissueRewardedAdDiamonds => false;
  bool get mayTreatMissingAsZero => false;
}
