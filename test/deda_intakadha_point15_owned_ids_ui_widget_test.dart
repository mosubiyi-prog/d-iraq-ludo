import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point15_fixture.dart';

void main() {
  const original = '@DEDA-AQPYXJ';
  const premium = '@DEDA-R001';
  String uid = 'verified_uid';
  var activeId = original;
  var reads = 0;
  var switches = 0;
  bool refuse = false;
  var isGm = false;

  DedaPoint15OwnedIdsSnapshot server() => DedaPoint15OwnedIdsSnapshot(
        accountUid: uid,
        originalId: original,
        activeId: activeId,
        ownedIds: [original, premium],
        serverConfirmed: true,
      );

  Widget app({String originalId = original, double width = 390}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Column(children: [
                DedaPoint15OwnedIdentifierPanel(originalId: originalId),
                const DedaPoint15AdminReservedGrantPanel(),
              ]),
            ),
          ),
        ),
      );

  Finder selected(String id) =>
      find.byKey(ValueKey<String>('deda_point15_select_' + id));

  Future<void> confirmUse(WidgetTester tester) async {
    await tester.ensureVisible(selected(premium));
    await tester.pumpAndSettle();
    await tester.tap(selected(premium));
    await tester.pumpAndSettle();
  }

  setUp(() {
    DedaPoint15OwnedIdsState.clearForLogout();
    uid = 'verified_uid';
    activeId = original;
    reads = 0;
    switches = 0;
    refuse = false;
    isGm = false;
    DedaPoint15OwnedIdsBridge.verifiedUid = () => uid;
    DedaPoint15OwnedIdsBridge.readRemote = () async {
      reads++;
      return server();
    };
    DedaPoint15OwnedIdsBridge.activateRemote = (wanted) async {
      switches++;
      if (refuse) throw StateError('offline');
      activeId = wanted;
      return server();
    };
    DedaPoint15OwnedIdsBridge.verifiedGeneralManagerRemote = () async => isGm;
    DedaPoint15OwnedIdsBridge.grantReservedRemote =
        (originalRecipient, reserved, color) async => true;
  });
  tearDown(() {
    DedaPoint15OwnedIdsBridge.verifiedUid = null;
    DedaPoint15OwnedIdsBridge.readRemote = null;
    DedaPoint15OwnedIdsBridge.activateRemote = null;
    DedaPoint15OwnedIdsBridge.verifiedGeneralManagerRemote = null;
    DedaPoint15OwnedIdsBridge.grantReservedRemote = null;
    DedaPoint15OwnedIdsState.clearForLogout();
  });

  testWidgets('without verified server no paid identifier can be activated',
      (tester) async {
    DedaPoint15OwnedIdsBridge.readRemote = null;
    DedaPoint15OwnedIdsBridge.activateRemote = null;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);
    expect(find.text(premium), findsNothing);
    expect(find.byKey(const Key('deda_point15_admin_grant_only')), findsNothing);
    expect(switches, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read only verified account shows both original and owned premium',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(reads, greaterThanOrEqualTo(1));
    expect(find.text(original), findsOneWidget);
    expect(find.text(premium), findsOneWidget);
    expect(find.text('مستخدم حاليًا'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(selected(premium)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel switch keeps original selected, no remote calls',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await confirmUse(tester);
    expect(find.textContaining('تبقى'), findsWidgets);
    await tester.tap(find.byKey(const Key('deda_point15_cancel_switch')));
    await tester.pumpAndSettle();
    expect(switches, 0);
    expect(DedaPoint15OwnedIdsState.current(original)?.activeId, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm owned switch requires server reread, original remains owned',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await confirmUse(tester);
    await tester.tap(find.byKey(const Key('deda_point15_confirm_switch')));
    await tester.pumpAndSettle();
    expect(switches, 1);
    expect(reads, greaterThanOrEqualTo(2));
    final selected = DedaPoint15OwnedIdsState.current(original);
    expect(selected?.activeId, premium);
    expect(selected?.ownedIds, [original, premium]);
    expect(find.text(original), findsOneWidget);
    expect(find.text(premium), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed switch leaves original selected', (tester) async {
    refuse = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await confirmUse(tester);
    await tester.tap(find.byKey(const Key('deda_point15_confirm_switch')));
    await tester.pumpAndSettle();
    expect(switches, 1);
    expect(DedaPoint15OwnedIdsState.current(original)?.activeId, original);
    expect(find.textContaining('المعرّف السابق محفوظ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server refusing readback does not update UI prematurely',
      (tester) async {
    DedaPoint15OwnedIdsBridge.readRemote = () async {
      reads++;
      return DedaPoint15OwnedIdsSnapshot(
        accountUid: uid,
        originalId: original,
        activeId: original,
        ownedIds: [original, premium],
        serverConfirmed: true,
      );
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await confirmUse(tester);
    await tester.tap(find.byKey(const Key('deda_point15_confirm_switch')));
    await tester.pumpAndSettle();
    expect(switches, 1);
    expect(DedaPoint15OwnedIdsState.current(original)?.activeId, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing login account prevents stale paid ID visibility',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text(premium), findsOneWidget);
    uid = 'another_verified_uid';
    DedaPoint15OwnedIdsBridge.readRemote = null;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(DedaPoint15OwnedIdsState.current(original), isNull);
    expect(find.text(premium), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late old account response cannot grant ID to newer login',
      (tester) async {
    final wait = Completer<DedaPoint15OwnedIdsSnapshot>();
    DedaPoint15OwnedIdsBridge.readRemote = () => wait.future;
    await tester.pumpWidget(app());
    await tester.pump();
    uid = 'new_login';
    await tester.pumpWidget(app(originalId: '@DEDA-SECOND'));
    wait.complete(DedaPoint15OwnedIdsSnapshot(
      accountUid: 'verified_uid',
      originalId: original,
      activeId: premium,
      ownedIds: [original, premium],
      serverConfirmed: true,
    ));
    await tester.pumpAndSettle();
    expect(DedaPoint15OwnedIdsState.current('@DEDA-SECOND'), isNull);
    expect(find.text(premium), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin grant panel hidden from non GM and offline by default',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_point15_admin_grant_only')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GM can confirm reserved name gift and choose color (UI-only)',
      (tester) async {
    isGm = true;
    String? target;
    String? gifted;
    DedaPremiumIdCardColor? color;
    DedaPoint15OwnedIdsBridge.grantReservedRemote = (to, id, style) async {
      target = to;
      gifted = id;
      color = style;
      return true;
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_point15_admin_grant_only')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('deda_point15_recipient_input')), '@DEDA-123456');
    await tester.enterText(
      find.byKey(const Key('deda_point15_reserved_input')), '@DEDA-R001');
    await tester.ensureVisible(find.byKey(const Key('deda_point15_grant_button')));
    await tester.tap(find.byKey(const Key('deda_point15_grant_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deda_point15_confirm_grant')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deda_point15_confirm_grant')));
    await tester.pumpAndSettle();
    expect(target, '@DEDA-123456');
    expect(gifted, '@DEDA-R001');
    expect(color, DedaPremiumIdCardColor.gold);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mismatched active unowned ID is never displayed as verified',
      (tester) async {
    DedaPoint15OwnedIdsBridge.readRemote = () async =>
        DedaPoint15OwnedIdsSnapshot(
          accountUid: uid,
          originalId: original,
          activeId: '@DEDA-NOTOWN',
          ownedIds: [original, premium],
          serverConfirmed: true,
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(DedaPoint15OwnedIdsState.current(original), isNull);
    expect(find.text(premium), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
