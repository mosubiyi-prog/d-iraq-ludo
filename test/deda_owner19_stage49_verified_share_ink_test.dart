import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage48_verified_active_profile_ink.dart';
import 'package:d_iraq_ludo/deda_stage49_verified_share_id_badge.dart';
import 'package:d_iraq_ludo/deda_verified_identifier_ink.dart';

void main() {
  const original = '@DEDA-A1B2C3';
  const premium = '@DEDA-SALEM';
  const uid = 'verifiedAccount42';

  DedaStage48ActiveInkProof proof({
    String accountUid = uid,
    String originalId = original,
    String activeId = premium,
    String? color = 'diamond',
  }) =>
      DedaStage48ActiveInkProof(
        accountUid: accountUid,
        originalId: originalId,
        activeId: activeId,
        permanentColor: color,
      );

  Future<void> render(
    WidgetTester tester, {
    DedaStage48ActiveInkProof? state,
    String? account = uid,
    String identifier = original,
    bool arabic = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text(original, key: Key('original_canonical_qr_label')),
            DedaStage49VerifiedShareIdPreview(
              originalId: identifier,
              currentUid: account,
              verified: state,
              isArabic: arabic,
            ),
          ],
        ),
      ),
    ));
  }

  testWidgets('unverified, same-original and cross-account share never colored',
      (tester) async {
    for (final state in <DedaStage48ActiveInkProof?>[
      null,
      proof(accountUid: 'other-user'),
      proof(originalId: '@DEDA-Z1Z2Z3'),
      proof(activeId: original, color: null),
      proof(color: null),
      proof(color: 'invalid'),
    ]) {
      await render(tester, state: state);
      expect(find.byType(DedaVerifiedIdentifierText), findsNothing);
      expect(find.byKey(const Key('original_canonical_qr_label')),
          findsOneWidget);
    }
    await render(tester, state: proof(), account: null);
    expect(find.byType(DedaVerifiedIdentifierText), findsNothing);
  });

  testWidgets('premium glyph uses real immutable diamond text ink', (tester) async {
    await render(tester, state: proof());
    expect(find.text(original), findsOneWidget);
    expect(find.text(premium), findsOneWidget);
    final label = tester.widget<Text>(find.text(premium));
    expect(label.style?.color, const Color(0xFF87CEF7));
    expect(label.textDirection, TextDirection.ltr);
    expect(find.textContaining('المشاركة والرمز أعلاه'), findsOneWidget);
    expect(find.byType(QrShareInsecureFakeAction), findsNothing);
  });

  testWidgets('English text clarifies canonical original share behavior',
      (tester) async {
    await render(tester, state: proof(color: 'gold'), arabic: false);
    expect(find.textContaining('Sharing and the QR above still use your original ID.'),
        findsOneWidget);
    expect(tester.widget<Text>(find.text(premium)).style?.color,
        const Color(0xFFF2C463));
  });

  testWidgets('Stage49 actual remote badge stays invisible while both flags OFF',
      (tester) async {
    expect(DedaStage48ActiveInkBridge.enabled, false);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaStage49VerifiedShareIdBadge(
          originalId: original, isArabic: true),
      ),
    ));
    expect(find.byType(DedaVerifiedIdentifierText), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

// Compile-time only: never create a second actual button or QR routing.
class QrShareInsecureFakeAction extends StatelessWidget {
  const QrShareInsecureFakeAction({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
