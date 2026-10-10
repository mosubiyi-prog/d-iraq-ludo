import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_gift_recipient_preview.dart';

void main() {
  testWidgets('shows public profile name, DEDA ID and level before gifting',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaGiftRecipientPreview(
          isArabic: true,
          profile: {
            'displayName': 'مستخدم DEDA',
            'publicId': '@DEDA-7K4M9Q',
            'avatarStyle': 2,
            'frameStyle': 3,
            'level': 4,
          },
        ),
      ),
    ));
    expect(find.text('مستخدم DEDA'), findsOneWidget);
    expect(find.text('@DEDA-7K4M9Q'), findsOneWidget);
    expect(find.text('المستوى 4'), findsOneWidget);
    expect(find.text('تأكد من حساب المستلم'), findsOneWidget);
    expect(find.byKey(const Key('dedaVerifiedGiftRecipientProfile')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not expose private phone, UID or other account fields',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaGiftRecipientPreview(
          isArabic: true,
          profile: {
            'displayName': 'الأختبار',
            'publicId': '@DEDA-AQPYXJ',
            'phone': '07123456789',
            'email': 'private@example.com',
            'ownerUid': 'FirebasePrivateUidABC',
            'pin': '123456',
          },
        ),
      ),
    ));
    expect(find.text('07123456789'), findsNothing);
    expect(find.text('private@example.com'), findsNothing);
    expect(find.text('FirebasePrivateUidABC'), findsNothing);
    expect(find.text('123456'), findsNothing);
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
  });

  testWidgets('long user names do not overflow on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DedaGiftRecipientPreview(
            isArabic: true,
            profile: {
              'displayName': 'اسم طويل جدًا لمستخدم تجريبي في تطبيق DEDA الدليل الدقيق',
              'publicId': '@DEDA-LONGNAME',
              'frameStyle': 999,
              'avatarStyle': -2,
              'level': -100,
            },
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('@DEDA-LONGNAME'), findsOneWidget);
    expect(find.text('المستوى 1'), findsOneWidget);
  });
}
