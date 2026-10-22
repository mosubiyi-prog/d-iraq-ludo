import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_my_store_owned_profile_staged.dart';

void main() {
  const original = '@DEDA-AQPYXJ';
  const uid = 'verified-phone-owner-A';

  test('Point12 release is OFF before verified inventory rollout', () {
    expect(DedaMyStorePage.releaseEnabled, isFalse);
  });

  test('Point12 only authenticated original account may view owned items', () {
    const proof = DedaMyStoreSnapshot(
      ownerUid: uid,
      originalId: original,
      serverConfirmed: true,
      entries: <DedaMyStoreEntry>[
        DedaMyStoreEntry(kind: DedaMyStoreKind.identifier,
            itemId: original, displayName: original,
            origin: DedaMyStoreOrigin.free, active: false),
        DedaMyStoreEntry(kind: DedaMyStoreKind.identifier,
            itemId: '@DEDA-IRAQI', displayName: '@DEDA-IRAQI',
            origin: DedaMyStoreOrigin.granted, active: true),
        DedaMyStoreEntry(kind: DedaMyStoreKind.frame,
            itemId: 'frame_1', displayName: 'إطار مملوك',
            origin: DedaMyStoreOrigin.purchased, active: true),
      ],
    );
    expect(proof.verifiedFor(uid, original), isTrue);
    expect(proof.verifiedFor('other-account-uid', original), isFalse);
    expect(proof.verifiedFor(uid, '@DEDA-D62UEB'), isFalse);
    expect(const DedaMyStoreSnapshot(
      ownerUid: uid, originalId: original,
      serverConfirmed: false, entries: <DedaMyStoreEntry>[],
    ).verifiedFor(uid, original), isFalse);
    expect(proof.entries.where((x) => x.active).length, 2);
  });

  test('Point12 rejects duplicate entitlements, forged originals and double active frames',
      () {
    const fakeOriginal = DedaMyStoreSnapshot(
      ownerUid: uid, originalId: original, serverConfirmed: true,
      entries: <DedaMyStoreEntry>[
        DedaMyStoreEntry(kind: DedaMyStoreKind.identifier,
          itemId: '@DEDA-IRAQI', displayName: 'spoofed free ID',
          origin: DedaMyStoreOrigin.free, active: true),
      ],
    );
    expect(fakeOriginal.verifiedFor(uid, original), isFalse);
    const duplicate = DedaMyStoreEntry(kind: DedaMyStoreKind.frame,
        itemId: 'frame_3', displayName: 'Frame',
        origin: DedaMyStoreOrigin.purchased, active: false);
    const doubleOwned = DedaMyStoreSnapshot(
      ownerUid: uid, originalId: original, serverConfirmed: true,
      entries: <DedaMyStoreEntry>[duplicate, duplicate],
    );
    expect(doubleOwned.verifiedFor(uid, original), isFalse);
    const doubleActive = DedaMyStoreSnapshot(
      ownerUid: uid, originalId: original, serverConfirmed: true,
      entries: <DedaMyStoreEntry>[
        DedaMyStoreEntry(kind: DedaMyStoreKind.badge, itemId: 'badge_elite',
            displayName: 'متألق',
            origin: DedaMyStoreOrigin.purchased, active: true),
        DedaMyStoreEntry(kind: DedaMyStoreKind.badge, itemId: 'badge_royal',
            displayName: 'ملكي',
            origin: DedaMyStoreOrigin.granted, active: true),
      ],
    );
    expect(doubleActive.verifiedFor(uid, original), isFalse);
  });

  testWidgets('Point12 standalone My Store displays exactly five sections, no fake property or buy controls',
      (tester) async {
    tester.view.physicalSize = const Size(460, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaMyStorePage(originalId: original),
    ));
    await tester.pump();
    expect(find.text('متجري'), findsOneWidget);
    expect(find.byKey(const Key('deda_p12_ownership_unverified')),
        findsOneWidget);
    expect(find.byKey(const Key('deda_p12_read_only_heading')),
        findsOneWidget);
    for (final kind in DedaMyStoreKind.values) {
      expect(find.byKey(ValueKey<String>('deda_p12_section_' + kind.name)),
          findsOneWidget);
    }
    expect(DedaMyStoreKind.values.length, 5);
    expect(find.text('@DEDA-IRAQI'), findsNothing);
    expect(find.text('مكتسبة'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Point12 unverifiable premium inventory cannot leak into another account',
      (tester) async {
    const unsafe = DedaMyStoreSnapshot(
      ownerUid: uid, originalId: original, serverConfirmed: true,
      entries: <DedaMyStoreEntry>[
        DedaMyStoreEntry(kind: DedaMyStoreKind.identifier,
          itemId: '@DEDA-IRAQI', displayName: '@DEDA-IRAQI',
          origin: DedaMyStoreOrigin.granted, active: true),
      ],
    );
    await tester.pumpWidget(const MaterialApp(home: DedaMyStorePage(
      originalId: '@DEDA-D62UEB',
      verifiedSnapshot: unsafe,
    )));
    await tester.pump();
    expect(find.text('@DEDA-IRAQI'), findsNothing);
    expect(find.byKey(const Key('deda_p12_ownership_unverified')),
        findsOneWidget);
  });
}
