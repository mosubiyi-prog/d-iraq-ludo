from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = {
    'account scope helper': 'static String _accountScope()',
    'stable account key source': 'DedaBackend.accountKeyForPhone(DedaPreferences.phone)',
    'sanitized account scope': "RegExp(r'[^A-Za-z0-9]')",
    'account scoped distance key': "'deda_long_trip_progress_m_v2_${_accountScope()}'",
    'account scoped day key': "'deda_long_trip_progress_day_v2_${_accountScope()}'",
    'trip progress load': 'var longTripProgress = await DedaLongTripProgress.load();',
    'trip reset': 'await DedaLongTripProgress.resetForNewTrip();',
    'trip update': 'DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)',
    'trip completion migration': 'if (longTripCompleted && longTripProgress < 1000)',
}
for label, marker in required.items():
    if marker not in text:
        raise SystemExit(f'Missing {label}: {marker}')

forbidden = {
    'old global distance key': "static const String _distanceKey = 'deda_long_trip_progress_m_v1';",
    'old global day key': "static const String _dayKey = 'deda_long_trip_progress_day_v1';",
}
for label, marker in forbidden.items():
    if marker in text:
        raise SystemExit(f'Forbidden {label} still present')

# The account suffix must be part of both SharedPreferences keys so switching
# accounts on the same Android device cannot inherit another user's metres.
if text.count('_accountScope()}') < 2:
    raise SystemExit('Trip progress SharedPreferences keys are not both account scoped')

print('Build 100256 account-scoped long-trip progress validation passed.')
