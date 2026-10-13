import 'package:flutter/material.dart';

/// Visual hints only. Never changes a place's saved category until its owner
/// explicitly taps the suggestion. No network calls, brand databases or logos.
class DedaPlaceSuggestion {
  final String categoryCode;
  final String arabicLabel;
  final String englishLabel;
  final String customArabicType;
  final IconData icon;

  const DedaPlaceSuggestion({
    required this.categoryCode,
    required this.arabicLabel,
    required this.englishLabel,
    required this.icon,
    this.customArabicType = '',
  });
}

class DedaPlaceSuggestions {
  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064b-\u065f\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _contains(String input, List<String> keywords) =>
      keywords.any((keyword) => input.contains(_normalize(keyword)));

  /// Returns at most two suggestions. A word in the place name is not proof
  /// of a legal business category: selection is always a user action.
  static List<DedaPlaceSuggestion> forName(String placeName) {
    final name = _normalize(placeName);
    if (name.length < 3) return const [];

    // Heartbeat professional activities: specific Iraqi trades BEFORE the
    // generic "محل/متجر" matcher, so a shop name never hides its trade.
    if (_contains(name, ['صالون نسائي', 'صالون نسائي', 'كوافير', 'مركز تجميل نسائي', 'تصفيف نسائي', 'حلاقة نسائية', 'حلاق نسائي', 'beauty salon', 'ladies salon'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'صالون نسائي',
        englishLabel: 'Ladies hair salon', customArabicType: 'صالون نسائي',
        icon: Icons.face_retouching_natural,
      )];
    }
    if (_contains(name, ['حلاق', 'حلاقة', 'حلاقه', 'صالون رجالي', 'barber', 'barbershop'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'حلاقة رجالية',
        englishLabel: 'Barber shop', customArabicType: 'حلاقة رجالية',
        icon: Icons.content_cut,
      )];
    }
    if (_contains(name, ['انشائية', 'إنشائية', 'مواد بناء', 'سمنت', 'اسمنت', 'طابوق', 'حديد تسليح', 'building materials', 'construction supplies'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'مواد بناء / إنشائية',
        englishLabel: 'Building materials', customArabicType: 'مواد بناء',
        icon: Icons.construction,
      )];
    }
    if (_contains(name, ['ميكانيكي', 'ميكانيك', 'تصليح سيارات', 'صيانة سيارات', 'كهربائي سيارات', 'auto repair', 'mechanic'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'تصليح سيارات',
        englishLabel: 'Auto repair', customArabicType: 'تصليح سيارات',
        icon: Icons.car_repair,
      )];
    }
    if (_contains(name, ['مخبز', 'فرن', 'معجنات', 'bread bakery', 'bakery'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'مخبز',
        englishLabel: 'Bakery', customArabicType: 'مخبز',
        icon: Icons.bakery_dining,
      )];
    }
    if (_contains(name, ['ملابس', 'البسة', 'ألبسة', 'بوتيك', 'fashion', 'clothing'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'ملابس',
        englishLabel: 'Clothing', customArabicType: 'ملابس',
        icon: Icons.checkroom,
      )];
    }
    if (_contains(name, ['هواتف', 'موبايلات', 'موبايل', 'جوال', 'اتصالات', 'mobile phones', 'phone repair'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'هواتف',
        englishLabel: 'Mobile phones', customArabicType: 'هواتف',
        icon: Icons.phone_android,
      )];
    }
    if (_contains(name, ['مكتبة', 'قرطاسية', 'مستلزمات مدرسية', 'stationery', 'bookshop'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'مكتبة / قرطاسية',
        englishLabel: 'Stationery', customArabicType: 'مكتبة',
        icon: Icons.menu_book,
      )];
    }
    if (_contains(name, ['خياطة', 'خياط', 'تفصيل ملابس', 'tailor'])) {
      return const [DedaPlaceSuggestion(
        categoryCode: 'other', arabicLabel: 'خياطة',
        englishLabel: 'Tailor', customArabicType: 'خياطة',
        icon: Icons.design_services,
      )];
    }
    if (_contains(name, ['منفذ', 'كي كارد', 'qi card', 'ماستر كارد', 'دفع إلكتروني'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'other',
          arabicLabel: 'منفذ دفع إلكتروني',
          englishLabel: 'Electronic payment outlet',
          customArabicType: 'منفذ دفع إلكتروني',
          icon: Icons.credit_card_outlined,
        ),
        DedaPlaceSuggestion(
          categoryCode: 'other',
          arabicLabel: 'منفذ خدمات',
          englishLabel: 'Service outlet',
          customArabicType: 'منفذ خدمات',
          icon: Icons.storefront_outlined,
        ),
      ];
    }
    if (_contains(name, ['غسل', 'غسيل', 'مغسلة سيارات', 'غسل سيارات', 'car wash'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'other',
          arabicLabel: 'غسل سيارات',
          englishLabel: 'Car wash',
          customArabicType: 'غسل سيارات',
          icon: Icons.local_car_wash,
        ),
      ];
    }
    if (_contains(name, ['صيدلية', 'صيدليه', 'pharmacy', 'drugstore'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'pharmacy',
          arabicLabel: 'صيدلية',
          englishLabel: 'Pharmacy',
          icon: Icons.local_pharmacy,
        ),
      ];
    }
    if (_contains(name, ['فندق', 'hotel', 'نزل'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'hotel',
          arabicLabel: 'فندق',
          englishLabel: 'Hotel',
          icon: Icons.hotel,
        ),
      ];
    }
    if (_contains(name, ['مطعم', 'restaurant', 'مشويات'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'restaurant',
          arabicLabel: 'مطعم',
          englishLabel: 'Restaurant',
          icon: Icons.restaurant,
        ),
      ];
    }
    if (_contains(name, ['محطة وقود', 'بنزين', 'gas station', 'fuel'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'fuel',
          arabicLabel: 'محطة وقود',
          englishLabel: 'Fuel station',
          icon: Icons.local_gas_station,
        ),
      ];
    }
    if (_contains(name, ['مول', 'mall'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'mall',
          arabicLabel: 'مول',
          englishLabel: 'Shopping mall',
          icon: Icons.local_mall,
        ),
      ];
    }
    if (_contains(name, ['أسواق', 'اسواق', 'سوق', 'ماركت', 'market', 'متجر', 'محل'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'shop',
          arabicLabel: 'متجر / أسواق',
          englishLabel: 'Shop / market',
          icon: Icons.shopping_bag_outlined,
        ),
      ];
    }
    if (_contains(name, ['كراج', 'garage'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'garage',
          arabicLabel: 'كراج',
          englishLabel: 'Garage',
          icon: Icons.garage_outlined,
        ),
      ];
    }
    if (_contains(name, ['مستشفى', 'hospital'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'hospital',
          arabicLabel: 'مستشفى',
          englishLabel: 'Hospital',
          icon: Icons.local_hospital,
        ),
      ];
    }
    if (_contains(name, ['حديقة', 'متنزه', 'park'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'park',
          arabicLabel: 'حديقة',
          englishLabel: 'Park',
          icon: Icons.park,
        ),
      ];
    }
    if (_contains(name, ['موقف', 'parking'])) {
      return const [
        DedaPlaceSuggestion(
          categoryCode: 'parking',
          arabicLabel: 'موقف',
          englishLabel: 'Parking',
          icon: Icons.local_parking,
        ),
      ];
    }
    return const [];
  }

  static IconData iconForCategory(String code, String customType) {
    switch (code) {
      case 'restaurant':
        return Icons.restaurant;
      case 'hotel':
        return Icons.hotel;
      case 'garage':
        return Icons.garage_outlined;
      case 'shop':
        return Icons.shopping_bag_outlined;
      case 'hospital':
        return Icons.local_hospital;
      case 'tourism':
        return Icons.tour;
      case 'mall':
        return Icons.local_mall;
      case 'fuel':
        return Icons.local_gas_station;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'parking':
        return Icons.local_parking;
      case 'park':
        return Icons.park;
      case 'other':
        // Category-specific activity icons (no store-by-default for known trades).
        final normalized = _normalize(customType);
        if (_contains(normalized, ['صالون نسائي', 'كوافير', 'تجميل نسائي', 'حلاقة نسائية', 'حلاق نسائي'])) {
          return Icons.face_retouching_natural;
        }
        if (_contains(normalized, ['حلاق', 'حلاقة', 'حلاقه', 'barber'])) {
          return Icons.content_cut;
        }
        if (_contains(normalized, ['انشائية', 'مواد بناء', 'اسمنت', 'سمنت', 'طابوق', 'حديد تسليح'])) {
          return Icons.construction;
        }
        if (_contains(normalized, ['تصليح سيارات', 'ميكانيك', 'صيانة سيارات'])) {
          return Icons.car_repair;
        }
        if (_contains(normalized, ['مخبز', 'فرن', 'معجنات'])) {
          return Icons.bakery_dining;
        }
        if (_contains(normalized, ['ملابس', 'بوتيك', 'البسة'])) {
          return Icons.checkroom;
        }
        if (_contains(normalized, ['هواتف', 'موبايل', 'اتصالات'])) {
          return Icons.phone_android;
        }
        if (_contains(normalized, ['مكتبة', 'قرطاسية'])) {
          return Icons.menu_book;
        }
        if (_contains(normalized, ['خياط', 'خياطة'])) {
          return Icons.design_services;
        }
        if (_contains(normalized, ['غسل', 'غسيل', 'car wash'])) {
          return Icons.local_car_wash;
        }
        if (_contains(_normalize(customType), ['دفع', 'كي كارد', 'بطاقة'])) {
          return Icons.credit_card_outlined;
        }
        if (_contains(_normalize(customType), ['منفذ', 'خدمات'])) {
          return Icons.storefront_outlined;
        }
        return Icons.storefront_outlined;
      default:
        return Icons.storefront_outlined;
    }
  }

  /// Returns an activity-specific symbol, independent of owner photo uploads.
  /// Known trades use the same symbol in owner profile and on map.
  /// Empty means use the regular Material icon for this category.
  static String emojiForCategory(String category, String customType, {String placeName = ''}) {
    if (category != 'other') return '';
    final type = _normalize(customType);
    // Explicit profession takes priority; infer from name only as a fallback.
    final inferred = type.isEmpty ? forName(placeName) : const <DedaPlaceSuggestion>[];
    final value = type.isEmpty && inferred.isNotEmpty
        ? _normalize(inferred.first.customArabicType) : type;
    if (_contains(value, ['صالون نسائي', 'كوافير', 'تجميل نسائي', 'حلاقة نسائية', 'حلاق نسائي'])) {
      return '💇‍♀️';
    }
    if (_contains(value, ['حلاق', 'حلاقة', 'حلاقه', 'barber'])) return '💈';
    if (_contains(value, ['انشائية', 'مواد بناء', 'سمنت', 'اسمنت', 'طابوق', 'حديد تسليح'])) return '🧱';
    if (_contains(value, ['مخبز', 'فرن', 'معجنات'])) return '🥖';
    if (_contains(value, ['غسل سيارات', 'غسيل سيارات', 'مغسلة سيارات', 'car wash'])) return '🚙';
    return '';
  }
}
