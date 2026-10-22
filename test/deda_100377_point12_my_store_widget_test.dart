import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100377_my_store_page_staged.dart';

void main() {
  testWidgets('royal frame inventory shows its genuine Flutter image asset, not a numeric placeholder', (tester) async {
    const asset = 'assets/deda_royal_frames/royal_frame_0.webp';
    await tester.pumpWidget(const MaterialApp(
      home: DedaMyStorePage(
        originalId: '@DEDA-AQPYXJ',
        items: <DedaMyStoreItem>[
          DedaMyStoreItem(
            id: 'free_frame_3',
            label: 'وردي ملكي',
            section: DedaMyStoreSection.frames,
            proof: DedaMyStoreProof.basicFree,
            previewAsset: asset,
            active: true,
          ),
        ],
      ),
    ));
    expect(find.text('وردي ملكي'), findsOneWidget);
    expect(find.text('الإطار المجاني 3'), findsNothing);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, asset);
    expect(find.text('مستخدمة'), findsOneWidget);
    expect(find.text('شراء مثبت بالخادم'), findsNothing);
  });

  testWidgets('original identifier acquisition and Edit Profile remain linked inside only one My Store', (tester) async {
    var shopOpened = 0;
    var editOpened = 0;
    await tester.pumpWidget(MaterialApp(
      home: DedaMyStorePage(
        originalId: '@DEDA-AQPYXJ',
        items: const <DedaMyStoreItem>[],
        onOpenIdentifierShop: () { shopOpened++; },
        onOpenEditProfile: () { editOpened++; },
      ),
    ));
    final edit = find.byKey(const Key('deda_p12_original_edit_profile_entry'));
    final shop = find.byKey(const Key('deda_p12_original_identifier_shop_entry'));
    expect(edit, findsOneWidget);
    expect(shop, findsOneWidget);
    await tester.tap(edit);
    await tester.pump();
    await tester.tap(shop);
    await tester.pump();
    expect(editOpened, 1);
    expect(shopOpened, 1);
    expect(find.byKey(const Key('deda_p12_no_fake_ownership_or_checkout')), findsOneWidget);
  });

  testWidgets('point12 always shows six separate personal-inventory sections',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaMyStorePage(
        originalId: '@DEDA-AQPYXJ',
        items: <DedaMyStoreItem>[],
      ),
    ));
    expect(find.text('متجري'), findsOneWidget);
    expect(find.byKey(const Key('deda_p12_no_fake_ownership_or_checkout')),
        findsOneWidget);
    expect(find.byKey(const Key('deda_p12_canonical_original_id')),
        findsOneWidget);
    for (final section in DedaMyStoreSection.values) {
      expect(
        find.byKey(ValueKey<String>('deda_p12_section_${section.name}')),
        findsOneWidget,
      );
    }
    expect(find.textContaining('شراء مثبت بالخادم'), findsNothing);
    expect(find.textContaining('هدية مثبتة بالخادم'), findsNothing);
    expect(find.text('شراء'), findsNothing);
  });

  testWidgets('device-saved badge is NOT a verified purchase or a gift',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaMyStorePage(
        originalId: '@DEDA-AQPYXJ',
        items: <DedaMyStoreItem>[
          DedaMyStoreItem(
            id: 'badge_spark', label: 'متألق',
            section: DedaMyStoreSection.badges,
            proof: DedaMyStoreProof.deviceSaved,
            active: true, receiptKind: 'purchase',
          ),
        ],
      ),
    ));
    expect(find.text('متألق'), findsOneWidget);
    expect(find.text('محفوظ على هذا الجهاز'), findsOneWidget);
    expect(
      find.byKey(const Key('deda_p12_empty_purchasedAndGranted')),
      findsOneWidget,
    );
    expect(find.text('شراء مثبت بالخادم'), findsNothing);
  });

  testWidgets('only verified server receipt qualifies in purchases/gifts',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaMyStorePage(
        originalId: '@DEDA-AQPYXJ',
        items: <DedaMyStoreItem>[
          DedaMyStoreItem(
            id: 'premium_lab_a', label: 'إطار مؤكد',
            section: DedaMyStoreSection.frames,
            proof: DedaMyStoreProof.serverVerified,
            receiptKind: 'purchase', active: true,
          ),
          DedaMyStoreItem(
            id: '@DEDA-IRAQI', label: '@DEDA-IRAQI',
            section: DedaMyStoreSection.identifiers,
            proof: DedaMyStoreProof.serverVerified,
            // Verified ACTIVE alone is not a gift or purchase receipt.
          ),
        ],
      ),
    ));
    expect(
      find.byKey(const Key('deda_p12_item_frames_premium_lab_a')),
      findsNWidgets(2),
    );
    expect(find.text('شراء مثبت بالخادم'), findsNWidgets(2));
    expect(find.text('هدية مثبتة بالخادم'), findsNothing);
  });
}
