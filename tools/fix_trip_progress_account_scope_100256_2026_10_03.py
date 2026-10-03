from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old = """class DedaLongTripProgress {\n  static const String _distanceKey = 'deda_long_trip_progress_m_v1';\n  static const String _dayKey = 'deda_long_trip_progress_day_v1';\n  static final ValueNotifier<double> distanceNotifier = ValueNotifier<double>(0);\n"""

new = """class DedaLongTripProgress {\n  static final ValueNotifier<double> distanceNotifier = ValueNotifier<double>(0);\n\n  static String _accountScope() {\n    final raw = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();\n    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');\n    return cleaned.isEmpty ? 'guest' : cleaned;\n  }\n\n  static String get _distanceKey =>\n      'deda_long_trip_progress_m_v2_${_accountScope()}';\n  static String get _dayKey =>\n      'deda_long_trip_progress_day_v2_${_accountScope()}';\n"""

count = text.count(old)
if count != 1:
    raise SystemExit(f'Expected one DedaLongTripProgress key block, found {count}')

text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('Build 100256 account-scoped long-trip progress fix applied.')
