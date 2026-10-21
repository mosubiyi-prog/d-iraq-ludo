import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_active_account_scope.dart';

void main() {
  const ownerUid = 'verified-owner-uid';
  const original = '@DEDA-ABC123';
  test('own original may be displayed only with null premium color', () {
    const proof = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: original, fixedColor: null,
    );
    expect(proof.verifiedFor(ownerUid, original), isTrue);
    expect(proof.isPremium, isFalse);
  });

  test('confirmed premium ID and permanent color are valid for owner', () {
    const proof = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: '@DEDA-IRAQI', fixedColor: 'gold',
    );
    expect(proof.verifiedFor(ownerUid, original), isTrue);
    expect(proof.isPremium, isTrue);
  });

  test('same alias never leaks to a different UID or account', () {
    const proof = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: '@DEDA-IRAQI', fixedColor: 'gold',
    );
    expect(proof.verifiedFor('different-uid', original), isFalse);
    expect(proof.verifiedFor(ownerUid, '@DEDA-DEF456'), isFalse);
  });

  test('original ID cannot be falsely painted as owned premium', () {
    const proof = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: original, fixedColor: 'gold',
    );
    expect(proof.verifiedFor(ownerUid, original), isFalse);
  });

  test('invalid alias characters and unknown color are rejected', () {
    const invalidId = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: '@DEDA-BAD-ID', fixedColor: 'gold',
    );
    const invalidColor = DedaQa32ActiveAccountIdentity(
      uid: ownerUid, originalId: original,
      displayId: '@DEDA-IRAQI', fixedColor: 'locally-spoofed',
    );
    expect(invalidId.verifiedFor(ownerUid, original), isFalse);
    expect(invalidColor.verifiedFor(ownerUid, original), isFalse);
  });
  testWidgets('uninitialized Firebase never crashes account ID header',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaQa32ActiveAccountScope(
        originalId: original,
        builder: (context, proof) =>
            Text(proof == null ? 'original-safe-fallback' : 'verified-alias'),
      )),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('original-safe-fallback'), findsOneWidget);
  });

}
