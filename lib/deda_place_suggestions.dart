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
        if (_contains(_normalize(customType), ['غسل', 'غسيل', 'car wash'])) {
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
}
