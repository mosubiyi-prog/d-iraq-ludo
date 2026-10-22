import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage71_free_owned_use_profile.dart';
import 'package:d_iraq_ludo/deda_stage71_free_manager_200_service.dart';

void main() {
  const first = '@DEDA-AQPYXJ';
  const second = '@DEDA-D62UEB';

  testWidgets('Point09 switching visible owner never invents a premium foil',
      (tester) async {
    // Owner-tested server proofs require signed device QA. This test ensures
    // the default-off source never borrows another user's royal ID artwork.
    expect(DedaStage71Admin200.enabled, isFalse);
    Widget owner(String id) => MaterialApp(
          home: Scaffold(
            body: DedaStage71ActiveProfileFoil(
              originalId: id,
              fallback: Text('original-fallback-$id'),
            ),
          ),
        );
    await tester.pumpWidget(owner(first));
    await tester.pump();
    expect(find.text('original-fallback-$first'), findsOneWidget);
    await tester.pumpWidget(owner(second));
    await tester.pump();
    expect(find.text('original-fallback-$second'), findsOneWidget);
    expect(find.text('original-fallback-$first'), findsNothing);

    // A different widget may request an active-ID refresh; it still must
    // not manufacture a premium server grant/receipt or hijack the account.
    DedaStage71ActiveIdRefresh.changed();
    await tester.pump();
    expect(find.text('original-fallback-$second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Point09 owned ID panel is empty-safe on two fresh owners',
      (tester) async {
    Widget panel(String id) => MaterialApp(
          home: Scaffold(
            body: DedaStage71OwnedIdsPanel(originalId: id),
          ),
        );
    await tester.pumpWidget(panel(first));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(panel(second));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('@DEDA-IRAQI'), findsNothing);
    expect(find.text('@DEDA-SALEM'), findsNothing);
  });
}
