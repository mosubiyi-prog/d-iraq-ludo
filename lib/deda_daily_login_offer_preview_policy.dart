import 'deda_daily_task_slots.dart';

/// Stage 12 - local manager UI preview only.
///
/// Nothing from this file is stored on Firebase or used in an award claim.
/// The signed-off 10-point daily login continues untouched in main.dart.
/// A future trusted server clock + reward ledger are required for production.
enum DedaLoginPreviewUnit {
  points,
  coins,
  diamonds;

  String get key => name;

  String get titleAr => switch (this) {
        points => 'نقاط',
        coins => 'عملات',
        diamonds => 'ماسات',
      };

  String get titleEn => switch (this) {
        points => 'Points',
        coins => 'Coins',
        diamonds => 'Diamonds',
      };
}

class DedaLoginPreviewReward {
  const DedaLoginPreviewReward({
    required this.unit,
    required this.amount,
  });

  final DedaLoginPreviewUnit unit;
  final int amount;

  static const legacy = DedaLoginPreviewReward(
    unit: DedaLoginPreviewUnit.points,
    amount: DedaDailyTaskSlot.regularLoginPoints,
  );

  bool get valid => amount >= 1 && amount <= 5000;
}

class DedaLoginPreviewOffer {
  const DedaLoginPreviewOffer({
    required this.startDay,
    required this.endDay,
    required this.reward,
  });

  final String startDay;
  final String endDay;
  final DedaLoginPreviewReward reward;
}

class DedaLoginPreviewPlan {
  const DedaLoginPreviewPlan({
    required this.base,
    required this.offer,
  });

  final DedaLoginPreviewReward base;
  final DedaLoginPreviewOffer offer;

  /// There is intentionally no award or balance mutation API.
  bool get canGrantRewards => false;

  static DateTime? _parseDay(String day) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return null;
    final parsed = DateTime.tryParse(day + 'T00:00:00.000Z');
    if (parsed == null || _formatDay(parsed) != day) return null;
    return parsed;
  }

  static String _formatDay(DateTime value) =>
      value.year.toString().padLeft(4, '0') + '-' +
      value.month.toString().padLeft(2, '0') + '-' +
      value.day.toString().padLeft(2, '0');

  static String dayFromCalendarDate(DateTime value) =>
      _formatDay(DateTime.utc(value.year, value.month, value.day));

  static DateTime calendarDateFromDay(String day) {
    final date = _parseDay(day);
    if (date == null) throw FormatException('invalid-iraq-day');
    return DateTime(date.year, date.month, date.day);
  }

  static String dayAfter(String day) {
    final date = _parseDay(day);
    if (date == null) throw FormatException('invalid-iraq-day');
    return _formatDay(date.add(const Duration(days: 1)));
  }

  static String todayIraqFrom(DateTime instant) => DedaIraqDay.id(instant);

  /// Mirrors the Stage 11 server prototype's rules for ONE preview offer.
  /// Never use the phone's clock for entitlements or real payouts.
  String? validate({required String currentIraqDay}) {
    final today = _parseDay(currentIraqDay);
    final start = _parseDay(offer.startDay);
    final end = _parseDay(offer.endDay);
    if (today == null || start == null || end == null) {
      return 'invalid-day';
    }
    if (!base.valid || !offer.reward.valid) return 'invalid-amount';
    if (!start.isAfter(today)) return 'must-start-future-day';
    final days = end.difference(start).inDays + 1;
    if (days < 1 || days > 31) return 'invalid-offer-duration';
    if (start.difference(today).inDays > 366) {
      return 'too-far-in-future';
    }
    return null;
  }

  /// Display-only selection on an Iraqi civil day, inclusive of the end day.
  DedaLoginPreviewReward rewardForDay(String iraqDay) {
    if (_parseDay(iraqDay) == null) {
      throw FormatException('invalid-iraq-day');
    }
    if (iraqDay.compareTo(offer.startDay) >= 0 &&
        iraqDay.compareTo(offer.endDay) <= 0) {
      return offer.reward;
    }
    return base;
  }

  bool isOfferDay(String iraqDay) {
    if (_parseDay(iraqDay) == null) {
      throw FormatException('invalid-iraq-day');
    }
    return iraqDay.compareTo(offer.startDay) >= 0 &&
        iraqDay.compareTo(offer.endDay) <= 0;
  }
}
