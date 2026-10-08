/// Immutable identifiers for the eight existing DEDA user task cards.
/// Order matches DedaTaskIds.weekly in lib/main.dart. These are *slots*;
/// an administrative draft does NOT activate a reward or alter this list.
class DedaDailyTaskSlot {
  const DedaDailyTaskSlot({
    required this.id,
    required this.action,
    required this.titleAr,
    required this.subtitleAr,
  });

  final String id;
  final String action;
  final String titleAr;
  final String subtitleAr;

  String get draftId => 'daily_slot_$id';

  static const String loginTitleAr = 'تسجيل الدخول اليومي';
  static const int regularLoginPoints = 10;

  static const List<DedaDailyTaskSlot> slots = <DedaDailyTaskSlot>[
    DedaDailyTaskSlot(
      id: 'share_personal_location',
      action: 'share_personal_location',
      titleAr: 'شارك مكانك الشخصي',
      subtitleAr: 'شارك موقعك الحالي مع من تريد',
    ),
    DedaDailyTaskSlot(
      id: 'open_map',
      action: 'open_map',
      titleAr: 'افتح الخريطة',
      subtitleAr: 'حدد أو ابحث عن أي مكان على الخريطة',
    ),
    DedaDailyTaskSlot(
      id: 'share_registered_place',
      action: 'share_registered_place',
      titleAr: 'شارك إدارة مكانك إن وجد',
      subtitleAr: 'مهمة خاصة بصاحب المكان',
    ),
    DedaDailyTaskSlot(
      id: 'open_saved_place',
      action: 'open_saved_place',
      titleAr: 'زيارة مكان محفوظ',
      subtitleAr: 'قم بزيارة أحد الأماكن المحفوظة لديك',
    ),
    DedaDailyTaskSlot(
      id: 'open_received_place',
      action: 'open_received_place',
      titleAr: 'افتح أي مكان تمت مشاركته معك',
      subtitleAr: 'افتح وتصفح مكانًا تمت مشاركته معك',
    ),
    DedaDailyTaskSlot(
      id: 'review_added_place',
      action: 'review_added_place',
      titleAr: 'مراجعة مكان مضاف',
      subtitleAr: 'راجع تفاصيل مكان أضفته سابقًا',
    ),
    DedaDailyTaskSlot(
      id: 'traffic_skills',
      action: 'traffic_skills',
      titleAr: 'اختبر مهاراتك',
      subtitleAr: 'أسئلة المهارات المرورية',
    ),
    DedaDailyTaskSlot(
      id: 'long_trip',
      action: 'long_trip',
      titleAr: 'استفد من رحلتك الطويلة إن وجدت',
      subtitleAr: 'استخدم إحدى خدمات الطريق أثناء رحلتك',
    ),
  ];

  static DedaDailyTaskSlot? byId(String id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }
}

/// Calendar calculations use the Iraqi civil-day boundary (UTC+03:00).
/// The eventual SERVER publisher must use the same boundary and read a trusted
/// clock; local UI dates must never grant points, diamonds or coins.
class DedaIraqDay {
  static const Duration utcOffset = Duration(hours: 3);

  static String id(DateTime instant) {
    final iraq = instant.toUtc().add(utcOffset);
    return '${iraq.year.toString().padLeft(4, '0')}-'
        '${iraq.month.toString().padLeft(2, '0')}-'
        '${iraq.day.toString().padLeft(2, '0')}';
  }

  static DateTime nextMidnightUtc(DateTime instant) {
    final iraq = instant.toUtc().add(utcOffset);
    return DateTime.utc(iraq.year, iraq.month, iraq.day + 1)
        .subtract(utcOffset);
  }
}
