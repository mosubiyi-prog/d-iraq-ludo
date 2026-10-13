import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_place_suggestions.dart';

void main() {
  group('DEDA 100332 place-name visual suggestions', () {
    test('offers no guessed type for an unrelated or empty name', () {
      expect(DedaPlaceSuggestions.forName(''), isEmpty);
      expect(DedaPlaceSuggestions.forName('بيت أبو أحمد'), isEmpty);
      expect(DedaPlaceSuggestions.forName('اب'), isEmpty);
    });

    test('pharmacy remains an existing supported category', () {
      final results = DedaPlaceSuggestions.forName('صيدلية الشفاء');
      expect(results, hasLength(1));
      expect(results.single.categoryCode, 'pharmacy');
      expect(results.single.icon, Icons.local_pharmacy);
    });

    test('car wash uses existing other-category text without new schema', () {
      final results = DedaPlaceSuggestions.forName('غسل يونس العزاوي');
      expect(results, hasLength(1));
      expect(results.single.categoryCode, 'other');
      expect(results.single.customArabicType, 'غسل سيارات');
      expect(
        DedaPlaceSuggestions.iconForCategory('other', 'غسل سيارات'),
        Icons.local_car_wash,
      );
    });

    test('a vague payment outlet name offers two explicit choices', () {
      final results = DedaPlaceSuggestions.forName('منفذ الثقة الأهلي');
      expect(results, hasLength(2));
      expect(results[0].categoryCode, 'other');
      expect(results[1].categoryCode, 'other');
      expect(results[0].customArabicType, 'منفذ دفع إلكتروني');
      expect(results[1].customArabicType, 'منفذ خدمات');
      expect(
        DedaPlaceSuggestions.iconForCategory('other', 'منفذ دفع إلكتروني'),
        Icons.credit_card_outlined,
      );
    });

    test('commercial places show suitable activity suggestions', () {
      expect(DedaPlaceSuggestions.forName('فندق النخبة').single.categoryCode,
          'hotel');
      expect(DedaPlaceSuggestions.forName('أسواق الرافدين').single.categoryCode,
          'shop');
      expect(DedaPlaceSuggestions.forName('مطعم العائلة').single.categoryCode,
          'restaurant');
      expect(DedaPlaceSuggestions.forName('محطة وقود السلام').single.categoryCode,
          'fuel');
    });

    test('case-insensitive English keywords also work', () {
      expect(DedaPlaceSuggestions.forName('CITY PHARMACY').single.categoryCode,
          'pharmacy');
      expect(DedaPlaceSuggestions.forName('new CAR WASH').single.categoryCode,
          'other');
    });
  });

  group('DEDA Heartbeat: offline Iraqi professions and emoji identity', () {
    test('barber pole, women salon and building materials never look like stores', () {
      expect(DedaPlaceSuggestions.forName('حلاقة الأخوين').single.customArabicType,
          'حلاقة رجالية');
      expect(DedaPlaceSuggestions.emojiForCategory('other', 'حلاقة'), '💈');
      expect(DedaPlaceSuggestions.iconForCategory('other', 'حلاقة'),
          Icons.content_cut);

      expect(DedaPlaceSuggestions.forName('صالون نسائي زينة').single.customArabicType,
          'صالون نسائي');
      expect(DedaPlaceSuggestions.emojiForCategory('other', 'كوافير نسائي'), '💇‍♀️');
      expect(DedaPlaceSuggestions.forName('محل إنشائية أبو علي')
          .single.customArabicType, 'مواد بناء');
      expect(DedaPlaceSuggestions.emojiForCategory('other', 'إنشائية'), '🧱');
    });

    test('known specific profession wins over generic محل and other shop words', () {
      expect(DedaPlaceSuggestions.forName('محل تصليح سيارات').single.icon,
          Icons.car_repair);
      expect(DedaPlaceSuggestions.forName('محل ملابس الأطفال').single.icon,
          Icons.checkroom);
      expect(DedaPlaceSuggestions.forName('محل موبايلات').single.icon,
          Icons.phone_android);
      expect(DedaPlaceSuggestions.forName('مخبز باب الحارة').single.icon,
          Icons.bakery_dining);
    });

    test('differentiate unknown profession from determined or explicitly typed profession', () {
      expect(DedaPlaceSuggestions.emojiForCategory('other', 'خدمة مجهولة'), '');
      expect(DedaPlaceSuggestions.emojiForCategory('other', '', placeName: 'حلاقة الأخوين'),
          '💈');
      expect(DedaPlaceSuggestions.emojiForCategory('other', 'خدمة مجهولة',
          placeName: 'حلاقة الأخوين'), '');
      expect(DedaPlaceSuggestions.emojiForCategory('pharmacy', 'حلاق'), '');
      expect(DedaPlaceSuggestions.iconForCategory('pharmacy', ''), Icons.local_pharmacy);
    });
  });
}
