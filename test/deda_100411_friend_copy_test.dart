import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_friend_id_copy_100411.dart';

void main() {
  test('normal and premium ID are copied byte-for-byte, not reformatted', () {
    expect(DedaFriendIdCopy100411.exactCopyValue('@DEDA-ABC123'),
        '@DEDA-ABC123');
    expect(DedaFriendIdCopy100411.exactCopyValue('@DEDA-IRAQI'),
        '@DEDA-IRAQI');
    expect(DedaFriendIdCopy100411.exactCopyValue('@DEDA-ROYAL2026'),
        '@DEDA-ROYAL2026');
  });

  test('never copies comma, Arabic separator or bidirectional marks', () {
    for (final bad in [
      '@DEDA-ABC123,', '@DEDA-ABC123،',
      '\u200F@DEDA-ABC123', '@DEDA-ABC123\u200E',
      ' @DEDA-ABC123', '@DEDA-ABC123 ',
      '@DEDA-ABC 123', '@deda-abc123', '@DEDA-ABC-123',
    ]) {
      expect(DedaFriendIdCopy100411.exactCopyValue(bad), isNull,
          reason: bad);
    }
  });

  testWidgets('copy button transfers only the verified public display ID',
      (tester) async {
    String? actual;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        actual = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaFriendIdCopy100411(
          verifiedDisplayId: '@DEDA-IRAQI',
          child: Text('@DEDA-IRAQI', textDirection: TextDirection.ltr),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('deda_friend_id_copy_icon')));
    await tester.pump();
    expect(actual, '@DEDA-IRAQI');
    expect(find.text('تم نسخ آيدي الصديق'), findsOneWidget);
  });

  testWidgets('unknown alias never permits copying a retired original ID',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaFriendIdCopy100411(
          verifiedDisplayId: null,
          child: Text('جارِ تأكيد الآيدي...'),
        ),
      ),
    ));
    expect(find.byKey(const Key('deda_friend_id_copy_icon')), findsNothing);
    expect(find.byKey(const Key('deda_friend_id_copy_tap')), findsNothing);
  });
}
