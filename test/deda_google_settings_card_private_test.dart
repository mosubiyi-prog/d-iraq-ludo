import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step1_google_settings_link_100439.dart';
import 'package:d_iraq_ludo/deda_100433_owner_confirmation_ui.dart';
import 'package:d_iraq_ludo/deda_session_diagnostic_readonly_100441.dart';

void main() {
  testWidgets('Google account card stays hidden in protected default OFF build',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaGoogleSettingsLinkCard(
          phone: '9647712345678',
          originalId: '@DEDA-ABC123',
          isArabic: true,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('deda-google-link-settings-card')),
        findsNothing);
    expect(find.byKey(const ValueKey('deda-google-link-verified')),
        findsNothing);
  });

  test('matching original anonymous DEDA UID can proceed to existing confirmation only', () {
    const current = DedaSessionProbeReport(
      DedaProbeKind.anonymous,
      DedaProbeMatch.sameUid,
      DedaProbeMatch.sameUid,
      false,
      false,
    );
    expect(DedaSessionDiagnosticReadOnly
        .mayOfferOriginalAnonymousConfirmation(current), true);
    // A matching anonymous UID is only a route to explicit owner/PIN
    // confirmation, NOT permission to bind Google or restore assets.
    expect(DedaSessionDiagnosticReadOnly.mayOfferDetachedGoogleLink(current), false);
  });

  test('different/missing original owner record remains HOLD, not a Google session', () {
    for (final report in <DedaSessionProbeReport>[
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.differentUid, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.differentUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.unavailable, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.unavailable, false, false),
      const DedaSessionProbeReport(DedaProbeKind.linked,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, true, true),
      const DedaSessionProbeReport(DedaProbeKind.changed,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, true, false),
    ]) {
      expect(DedaSessionDiagnosticReadOnly
          .mayOfferOriginalAnonymousConfirmation(report), false);
    }
  });


  test('new account and historical account must not be conflated by Google prompt', () {
    final guidance = DedaGoogleAnonymousAccountGuidance.message(
      matchingOwnerRecords: true, isArabic: true);
    expect(guidance, contains('جديداً أم سابقاً'));
    expect(guidance, contains('بنفس UID'));
    expect(guidance, contains('لا تسجّل خروجك'));
    expect(guidance, isNot(contains('فوق «تسجيل الخروج»')));
    expect(guidance, isNot(contains('حساب ديدا الأصلي')));
    final english = DedaGoogleAnonymousAccountGuidance.message(
      matchingOwnerRecords: true, isArabic: false);
    expect(english, contains('new or historical'));
    expect(english, isNot(contains('This is your original')));
  });

  test('unverified anonymous session never offers Google as a substitute owner', () {
    for (final ar in [true, false]) {
      final guidance = DedaGoogleAnonymousAccountGuidance.message(
        matchingOwnerRecords: false, isArabic: ar);
      expect(guidance, isNot(contains('linked and confirmed')));
      expect(guidance, isNot(contains('تم ربط')));
      expect(guidance, isNot(contains('حساب ديدا الأصلي')));
    }
  });

  testWidgets('one Google-card entry reuses protected owner PIN confirmation', (tester) async {
    var confirmed = 0, continuing = 0;
    String? confirmedUid;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      DedaOwnerConfirmButton(
        phone: '07712345678', originalId: '@DEDA-ABC123',
        forTesting: true,
        confirm: (phone, pin, id) async {
          confirmed++;
          expect(phone, '07712345678');
          expect(pin, '123456');
          expect(id, '@DEDA-ABC123');
          return 'same-original-test-uid';
        },
        onConfirmed: (uid) async { continuing++; confirmedUid = uid; },
      ),
    )));
    await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('deda-owner-pin-input')), '123456');
    await tester.tap(find.byKey(const ValueKey('deda-owner-pin-submit')));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(continuing, 1);
    expect(confirmedUid, 'same-original-test-uid');
  });

  testWidgets('failed owner confirmation never proceeds to Google card callback', (tester) async {
    var continuing = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      DedaOwnerConfirmButton(
        phone: '07712345678', originalId: '@DEDA-ABC123',
        forTesting: true,
        confirm: (_, __, ___) async {
          throw StateError('immutable-uid-conflict');
        },
        onConfirmed: (_) async { continuing++; },
      ),
    )));
    await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('deda-owner-pin-input')), '123456');
    await tester.tap(find.byKey(const ValueKey('deda-owner-pin-submit')));
    await tester.pumpAndSettle();
    expect(continuing, 0);
    expect(find.textContaining('تعذر تأكيد الحساب بأمان'), findsOneWidget);
  });

  test('one-entry Google continuation always denies archive or UID uncertainty', () {
    bool allowed({bool sameUid = true, bool place = false,
      bool quiz = false, bool global = false}) =>
        DedaGoogleOneEntryContinuation.mayContinue(
          confirmedSameLinkedUid: sameUid,
          placeArchiveUnconfirmed: place,
          quizArchiveUnconfirmed: quiz,
          globalArchiveUnconfirmed: global,
        );
    expect(allowed(), isTrue);
    expect(allowed(sameUid: false), isFalse);
    expect(allowed(place: true), isFalse);
    expect(allowed(quiz: true), isFalse);
    expect(allowed(global: true), isFalse);
    expect(allowed(sameUid: false, place: true, quiz: true, global: true), isFalse);
  });
}
