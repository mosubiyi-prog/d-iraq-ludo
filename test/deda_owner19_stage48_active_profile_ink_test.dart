import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage48_verified_active_profile_ink.dart';

void main() {
  const original = '@DEDA-A1B2C3';
  const premium = '@DEDA-SALEM';
  const uid = 'authenticatedAccount42';
  Map<String, dynamic> serverRecord({
    String accountUid = uid,
    String originalId = original,
    String activeId = premium,
    String? permanentColor = 'gold',
  }) =>
      <String, dynamic>{
        'serverConfirmed': true,
        'accountUid': accountUid,
        'originalId': originalId,
        'activeId': activeId,
        'permanentColor': permanentColor,
      };

  test('same-account original + active verified premium color is accepted', () {
    for (final color in ['gold', 'diamond', 'royal', 'pink']) {
      final proof = DedaStage48ActiveInkProof.parse(
          serverRecord(permanentColor: color), uid, original);
      expect(proof.accountUid, uid);
      expect(proof.originalId, original);
      expect(proof.activeId, premium);
      expect(proof.permanentColor, color);
    }
    final purchaseProof = DedaStage48ActiveInkProof.parse(
        serverRecord(permanentColor: null), uid, original);
    expect(purchaseProof.permanentColor, isNull);
  });

  test('original ID never acquires another owned IDs exclusive ink', () {
    final own = DedaStage48ActiveInkProof.parse(
        serverRecord(activeId: original, permanentColor: null),
        uid, original);
    expect(own.activeId, original);
    expect(own.permanentColor, isNull);
    expect(
      () => DedaStage48ActiveInkProof.parse(
        serverRecord(activeId: original, permanentColor: 'pink'),
        uid, original),
      throwsStateError,
    );
  });

  test('forged UID, original, invalid ID, unconfirmed or extra fields fail',
      () {
    final changes = <Map<String, dynamic> Function()>[
      () => serverRecord(accountUid: 'differentUid'),
      () => serverRecord(originalId: '@DEDA-Z1Z2Z3'),
      () => serverRecord(activeId: '@DEDA-abc'),
      () => serverRecord(activeId: '@DEDA-Z'),
      () => serverRecord(permanentColor: 'test-color'),
      () => {...serverRecord(), 'serverConfirmed': false},
      () => {...serverRecord(), 'accountKey': 'private-value'},
      () => {...serverRecord()}..remove('originalId'),
    ];
    for (final change in changes) {
      expect(() => DedaStage48ActiveInkProof.parse(
          change(), uid, original), throwsStateError);
    }
  });

  testWidgets('both live flags OFF preserve exact original profile slot',
      (tester) async {
    expect(DedaStage48ActiveInkBridge.enabled, false);
    var builtPremium = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaStage48ActiveInkProfileSlot(
          originalId: original,
          width: 240,
          compact: false,
          fallback: const Text(original,
              key: Key('deda_stage48_approved_fallback')),
          premiumFoil: (id, color, callback) {
            builtPremium = true;
            return Text('$id:$color');
          },
        ),
      ),
    ));
    expect(find.byKey(const Key('deda_stage48_approved_fallback')),
        findsOneWidget);
    expect(builtPremium, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('original ID change while gated OFF does not change entitlement',
      (tester) async {
    Widget page(String id) => MaterialApp(
          home: Scaffold(
            body: DedaStage48ActiveInkProfileSlot(
              originalId: id,
              width: 240,
              compact: true,
              fallback: Text(id, key: const Key('approved_original')),
              premiumFoil: (identifier, color, copy) =>
                  Text('$identifier $color'),
            ),
          ),
        );
    await tester.pumpWidget(page(original));
    expect(find.text(original), findsOneWidget);
    await tester.pumpWidget(page('@DEDA-Z1Z2Z3'));
    expect(find.text('@DEDA-Z1Z2Z3'), findsOneWidget);
    expect(find.text(original), findsNothing);
  });
}
