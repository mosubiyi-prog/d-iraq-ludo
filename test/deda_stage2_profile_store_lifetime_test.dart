import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_my_store_page_staged.dart';
import 'package:d_iraq_ludo/deda_section_state.dart' show DedaSectionAccountChanges;
import 'package:d_iraq_ludo/deda_stage2_profile_owner_my_store_gate_2026_11_23.dart';

void main() {
  testWidgets('existing store expires permanently on account selection, even A-B-A',
      (tester) async {
    var edits = 0;
    var shops = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaStage2ProfileOwnerBoundMyStore(
        originalId: '@DEDA-ABC123',
        items: const <DedaMyStoreItem>[],
        initialUid: null,
        ownerStillCurrent: () => true,
        onOpenEditProfile: () { edits++; },
        onOpenIdentifierShop: () { shops++; },
      ),
    ));
    await tester.pump();
    final page = tester.widget<DedaMyStorePage>(find.byType(DedaMyStorePage));
    final edit = page.onOpenEditProfile!;
    final shop = page.onOpenIdentifierShop!;
    edit();
    shop();
    expect(edits, 1);
    expect(shops, 1);
    // Two explicit selections before a repaint: the old route cannot revive.
    DedaSectionAccountChanges.changed();
    DedaSectionAccountChanges.changed();
    edit();
    shop();
    expect(edits, 1);
    expect(shops, 1);
    await tester.pump();
    expect(find.byType(DedaMyStorePage), findsNothing);
    expect(find.text('تغيّر الحساب. أعد فتح متجري من الملف الحالي.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    DedaSectionAccountChanges.changed();
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale callback refuses owner mismatch before next frame',
      (tester) async {
    var ownerCurrent = true;
    var edits = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaStage2ProfileOwnerBoundMyStore(
        originalId: '@DEDA-ABC123',
        items: const <DedaMyStoreItem>[],
        initialUid: null,
        ownerStillCurrent: () => ownerCurrent,
        onOpenEditProfile: () { edits++; },
      ),
    ));
    await tester.pump();
    final edit = tester.widget<DedaMyStorePage>(find.byType(DedaMyStorePage))
        .onOpenEditProfile!;
    ownerCurrent = false;
    edit();
    ownerCurrent = true;
    edit();
    expect(edits, 0);
    await tester.pump();
    expect(find.byType(DedaMyStorePage), findsNothing);
  });
}
