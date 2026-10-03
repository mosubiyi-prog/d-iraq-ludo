from pathlib import Path
import re

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

# Match the 100254 helper after dart format. Keep this resilient to harmless
# whitespace/line-wrap changes so the account-scope patch cannot fail just
# because the formatter split ValueNotifier across lines.
pattern = re.compile(
    r"class DedaLongTripProgress\s*\{\s*"
    r"static const String _distanceKey\s*=\s*'deda_long_trip_progress_m_v1';\s*"
    r"static const String _dayKey\s*=\s*'deda_long_trip_progress_day_v1';\s*"
    r"static final ValueNotifier<double> distanceNotifier\s*=\s*"
    r"ValueNotifier<double>\(0\);",
    re.MULTILINE,
)

replacement = """class DedaLongTripProgress {
  static final ValueNotifier<double> distanceNotifier = ValueNotifier<double>(0);

  static String _accountScope() {
    final raw = DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return cleaned.isEmpty ? 'guest' : cleaned;
  }

  static String get _distanceKey =>
      'deda_long_trip_progress_m_v2_${_accountScope()}';
  static String get _dayKey =>
      'deda_long_trip_progress_day_v2_${_accountScope()}';"""

text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(
        f'Expected one formatted DedaLongTripProgress key block, found {count}'
    )

path.write_text(text, encoding='utf-8')
print('Build 100256 account-scoped long-trip progress fix applied.')
