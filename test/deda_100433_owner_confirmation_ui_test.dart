import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100433_owner_confirmation_ui.dart';

void main() {
  const original = '@DEDA-ABC123', phone = '07712345678';
  Widget harness({
    bool forTesting = false,
    Future<String> Function(String,String,String)? confirm,
  }) => MaterialApp(home:Scaffold(body:Center(child:
    DedaOwnerConfirmButton(
      phone:phone,originalId:original,
      forTesting:forTesting,confirm:confirm,
    ))));

  testWidgets('Normal signed production build shows NO owner-link control',
    (tester) async {
      await tester.pumpWidget(harness());
      expect(find.byKey(const ValueKey('deda-owner-confirm-action')),findsNothing);
    });

  testWidgets('Original owner explicitly confirms phone PIN without saving it',
    (tester) async {
      var calls=0,recvPhone='',recvPin='',recvOriginal='';
      await tester.pumpWidget(harness(forTesting:true,
        confirm:(p,pin,id) async {
          calls++;recvPhone=p;recvPin=pin;recvOriginal=id;
          return 'legacy_original_uid';
        }));
      await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deda-owner-pin-input')),findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('deda-owner-pin-input')),
        '735812');
      await tester.tap(find.byKey(const ValueKey('deda-owner-pin-submit')));
      await tester.pumpAndSettle();
      expect(calls,1);
      expect(recvPhone,phone);
      expect(recvOriginal,original);
      expect(recvPin,'735812');
      expect(find.textContaining('تم ربط'),findsOneWidget);
    });

  testWidgets('Cancel PIN dialog does not link any Firebase Auth UID',
    (tester) async {
      var calls=0;
      await tester.pumpWidget(harness(forTesting:true,
        confirm:(a,b,c) async {calls++;return 'should-not-run';}));
      await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء / Cancel'));
      await tester.pumpAndSettle();
      expect(calls,0);
    });

  testWidgets('Incorrect or incomplete PIN is not submitted',
    (tester) async {
      var calls=0;
      await tester.pumpWidget(harness(forTesting:true,
        confirm:(a,b,c) async {calls++;return 'never';}));
      await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('deda-owner-pin-input')),
        '12345');
      await tester.tap(find.byKey(const ValueKey('deda-owner-pin-submit')));
      await tester.pumpAndSettle();
      expect(calls,0);
      expect(find.byKey(const ValueKey('deda-owner-pin-input')),findsOneWidget);
      await tester.tap(find.text('إلغاء / Cancel'));
      await tester.pumpAndSettle();
    });

  testWidgets('Linking error is handled without publishing money or PIN',
    (tester) async {
      await tester.pumpWidget(harness(forTesting:true,
        confirm:(a,b,c) async => throw StateError('private-test-pin-rejected')));
      await tester.tap(find.byKey(const ValueKey('deda-owner-confirm-action')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('deda-owner-pin-input')),
        '888888');
      await tester.tap(find.byKey(const ValueKey('deda-owner-pin-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('تعذر تأكيد الحساب'),findsOneWidget);
      expect(find.textContaining('private-test-pin-rejected'),findsNothing);
    });
}
