import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step1_google_settings_link_100439.dart';
import 'package:d_iraq_ludo/deda_session_diagnostic_readonly_100441.dart';

void main() {
  testWidgets('Google account card stays hidden in protected default OFF build',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaGoogleSettingsLinkCard(
          phone: '9647712345678',
          originalId: '@DEDA-ABC123',
          isArabic: true,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('deda-google-link-settings-card')),
        findsNothing);
    expect(find.byKey(const ValueKey('deda-google-link-verified')),
        findsNothing);
  });

  test('matching original anonymous DEDA UID can proceed to existing confirmation only', () {
    const current = DedaSessionProbeReport(
      DedaProbeKind.anonymous,
      DedaProbeMatch.sameUid,
      DedaProbeMatch.sameUid,
      false,
      false,
    );
    expect(DedaSessionDiagnosticReadOnly
        .mayOfferOriginalAnonymousConfirmation(current), true);
    // A matching anonymous UID is only a route to explicit owner/PIN
    // confirmation, NOT permission to bind Google or restore assets.
    expect(DedaSessionDiagnosticReadOnly.mayOfferDetachedGoogleLink(current), false);
  });

  test('different/missing original owner record remains HOLD, not a Google session', () {
    for (final report in <DedaSessionProbeReport>[
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.differentUid, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.differentUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.unavailable, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.unavailable, false, false),
      const DedaSessionProbeReport(DedaProbeKind.linked,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, true, true),
      const DedaSessionProbeReport(DedaProbeKind.changed,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, false, false),
      const DedaSessionProbeReport(DedaProbeKind.anonymous,
          DedaProbeMatch.sameUid, DedaProbeMatch.sameUid, true, false),
    ]) {
      expect(DedaSessionDiagnosticReadOnly
          .mayOfferOriginalAnonymousConfirmation(report), false);
    }
  });

}
