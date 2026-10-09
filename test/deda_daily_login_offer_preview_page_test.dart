import 'package:d_iraq_ludo/deda_daily_login_offer_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget previewPage() => MaterialApp(
  home: DedaDailyLoginOfferPreviewPage(
    isArabic: true,
    previewReferenceUtc: DateTime.utc(2026, 10, 9, 12),
  ),
);

Future<void> tapPreview(WidgetTester tester) async {
  final preview = find.byKey(const Key('simulateLoginOffer'));
  await tester.ensureVisible(preview);
  await tester.pumpAndSettle();
  await tester.tap(preview);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Manager sees unchanged current login and preview-only warning',
      (tester) async {
    await tester.pumpWidget(previewPage());
    expect(find.textContaining('تسجيل الدخول اليومي ثابت'), findsOneWidget);
    expect(find.textContaining('10 نقاط يوميًا'), findsOneWidget);
    expect(find.byKey(const Key('regularAmount')), findsOneWidget);
    expect(find.byKey(const Key('offerAmount')), findsOneWidget);
    expect(find.byKey(const Key('chooseOfferDays')), findsOneWidget);
    expect(find.textContaining('لا تنشر عروضًا'), findsOneWidget);
    expect(find.byKey(const Key('loginPreviewResults')), findsNothing);
  });

  testWidgets('50 temporary coins return to 10 base points after expiry',
      (tester) async {
    await tester.pumpWidget(previewPage());
    await tapPreview(tester);
    expect(find.byKey(const Key('loginPreviewResults')), findsOneWidget);
    expect(find.text('50 عملات'), findsNWidgets(2));
    expect(find.text('10 نقاط'), findsNWidgets(2));
    expect(find.textContaining('الرجوع تلقائي'), findsOneWidget);
    expect(find.textContaining('ما انحفظ أي موعد'), findsOneWidget);
  });

  testWidgets('Invalid amount cannot show results or claim reward',
      (tester) async {
    await tester.pumpWidget(previewPage());
    final field = find.byKey(const Key('offerAmount'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '5001');
    await tapPreview(tester);
    expect(find.byKey(const Key('loginPreviewResults')), findsNothing);
    expect(find.textContaining('رقمًا من 1 إلى 5000'), findsOneWidget);
  });

  testWidgets('Clearing a preview removes it without a Firebase action',
      (tester) async {
    await tester.pumpWidget(previewPage());
    await tapPreview(tester);
    expect(find.byKey(const Key('loginPreviewResults')), findsOneWidget);
    final clear = find.text('مسح نتيجة المحاكاة');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loginPreviewResults')), findsNothing);
  });
}
