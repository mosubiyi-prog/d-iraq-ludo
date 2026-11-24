import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('existing settings persist in order and retain original storage keys', () async {
    SharedPreferences.setMockInitialValues({});
    final writes = [
      DedaPreferences.setVoiceEnabled(false),
      DedaPreferences.setVoiceEnabled(true),
      DedaPreferences.setSpeechRate(0.35),
      DedaPreferences.setSpeechRate(0.65),
      DedaPreferences.setDefaultTravelMode(DedaTravelMode.values.last),
      DedaPreferences.setDefaultMapStyle(DedaMapStyle.values.last),
    ];
    await Future.wait(writes);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deda_voice_enabled_v1'), isTrue);
    expect(DedaPreferences.navigationVoiceEnabled, isTrue);
    expect(prefs.getDouble('deda_speech_rate_v1'), 0.65);
    expect(DedaPreferences.speechRate, 0.65);
    expect(prefs.getString('deda_default_travel_mode_v1'), DedaTravelMode.values.last.name);
    expect(prefs.getString('deda_default_map_style_v1'), DedaMapStyle.values.last.name);
    expect(DedaPreferences.defaultTravelMode, DedaTravelMode.values.last);
    expect(DedaPreferences.defaultMapStyle, DedaMapStyle.values.last);
  });
  testWidgets('original settings keeps navigation, location, and logout controls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DedaSettingsPage()));
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    // Login is not performed; Firebase and optional Google remain disabled.
    expect(find.byKey(const ValueKey('deda-stage2-google-identity-card')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
