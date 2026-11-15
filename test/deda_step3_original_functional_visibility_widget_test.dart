import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_original_functional_id_policy_20261115.dart';
import '../lib/deda_unified_active_id_100410.dart';
import '../lib/deda_six_active_identity.dart';
import '../lib/deda_stage50_verified_friend_ink_badge.dart';
import '../lib/deda_cosmetic_premium_profile_20261115.dart';

void main() {
  const original = '@DEDA-AQPYXJ';
  const previouslyActivePremium = '@DEDA-IRAQI';

  setUp(DedaUnifiedActiveId100410.resetPublicForTest);

  test('original remains the one functional display despite old premium server projection', () {
    expect(DedaOriginalFunctionalIdPolicy20261115.originalOnly, isTrue);
    // A legacy premium grant/projection must not replace the canonical ID.
    expect(DedaUnifiedActiveId100410.accept(original, {
      'originalId': original,
      'activeId': previouslyActivePremium,
      'baseColor': 'gold',
      'updatedAt': 'old-verified',
    }), isTrue);
    for (final surface in <String>['friends', 'weekly', 'share', 'admin label']) {
      expect(DedaUnifiedActiveId100410.display(original), original,
          reason: surface);
    }
    final confirmed = DedaUnifiedActiveId100410.proof(original);
    expect(confirmed?.displayId, original);
    expect(confirmed?.fixedColor, isNull);
    expect(DedaUnifiedActiveId100410.display('@DEDA-!'), isNull);
  });

  testWidgets('unified public label draws original immediately without Firebase', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaUnifiedActiveIdLabel100410(originalId: original)),
    ));
    expect(find.text(original), findsOneWidget);
    expect(find.text(previouslyActivePremium), findsNothing);
    expect(find.textContaining('تأكيد'), findsNothing);
  });

  testWidgets('original account ID widget does not await any premium proof', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaSixActiveIdentity(originalId: original)),
    ));
    expect(find.text(original), findsOneWidget);
    expect(find.text(previouslyActivePremium), findsNothing);
  });

  testWidgets('friend premium artwork never replaces original fallback', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaStage50VerifiedFriendInkBadge(
        originalId: original,
        fallback: Text(original),
      )),
    ));
    expect(find.text(original), findsOneWidget);
  });

  testWidgets('optional cosmetic premium defaults to original when not locally activated', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaCosmeticPremiumProfileFoil20261115(
        originalId: original,
        fallback: Text(original),
      )),
    ));
    expect(find.text(original), findsOneWidget);
    expect(find.text(previouslyActivePremium), findsNothing);
  });
}
