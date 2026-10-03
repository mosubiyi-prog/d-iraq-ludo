from pathlib import Path
import re

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    text = text.replace(old, new, 1)


# Shared, daily-scoped progress store. It is reset at the start of every real
# DEDA navigation session and survives leaving the route page so the tasks page
# can show how much of the 1 km requirement has actually been travelled.
helper_marker = 'class DedaDailyTasksPage extends StatefulWidget {'
helper = r'''class DedaLongTripProgress {
  static const String _distanceKey = 'deda_long_trip_progress_m_v1';
  static const String _dayKey = 'deda_long_trip_progress_day_v1';
  static final ValueNotifier<double> distanceNotifier = ValueNotifier<double>(0);

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<double> load() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final storedDay = prefs.getString(_dayKey);
    if (storedDay != today) {
      await prefs.setString(_dayKey, today);
      await prefs.setDouble(_distanceKey, 0);
      distanceNotifier.value = 0;
      return 0;
    }
    final value = (prefs.getDouble(_distanceKey) ?? 0).clamp(0.0, 1000.0).toDouble();
    distanceNotifier.value = value;
    return value;
  }

  static Future<void> resetForNewTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dayKey, _todayKey());
    await prefs.setDouble(_distanceKey, 0);
    distanceNotifier.value = 0;
  }

  static Future<void> update(double meters) async {
    final value = meters.clamp(0.0, 1000.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dayKey, _todayKey());
    await prefs.setDouble(_distanceKey, value);
    distanceNotifier.value = value;
  }
}

'''
replace_once(helper_marker, helper + helper_marker, 'long trip shared progress helper')

# Load the persisted progress whenever the daily-tasks page opens.
replace_once(
    'class _DedaDailyTasksPageState extends State<DedaDailyTasksPage> {\n'
    '  bool _loginRewardClaimed = false;\n',
    'class _DedaDailyTasksPageState extends State<DedaDailyTasksPage> {\n'
    '  double _longTripProgressMeters = 0;\n'
    '  bool _loginRewardClaimed = false;\n',
    'daily task progress field',
)

old_load = '''  Future<void> _loadRewardState() async {
    final claimed = await DedaTaskEngine.hasDailyLoginRewardClaimed();
    if (!mounted) return;
    setState(() {
      _loginRewardClaimed = claimed;
      _loadingRewardState = false;
    });
  }
'''
new_load = '''  Future<void> _loadRewardState() async {
    final claimed = await DedaTaskEngine.hasDailyLoginRewardClaimed();
    final longTripProgress = await DedaLongTripProgress.load();
    if (!mounted) return;
    setState(() {
      _longTripProgressMeters = longTripProgress;
      _loginRewardClaimed = claimed;
      _loadingRewardState = false;
    });
  }

  String _longTripProgressText() {
    final travelled = _longTripProgressMeters.clamp(0.0, 1000.0).toDouble();
    final remaining = (1000.0 - travelled).clamp(0.0, 1000.0).toDouble();
    final travelledKm = (travelled / 1000).toStringAsFixed(2);
    if (remaining <= 0.5) {
      return dedaText(
        'قطعت 1.00 كم • اكتملت المسافة المطلوبة',
        'Travelled 1.00 km • required distance completed',
      );
    }
    return dedaText(
      'قطعت $travelledKm كم • المتبقي ${remaining.round()} متر',
      'Travelled $travelledKm km • ${remaining.round()} m remaining',
    );
  }
'''
replace_once(old_load, new_load, 'load/display long trip progress')

# The previous 100253 patch made the requirement explicit. Turn that fixed
# subtitle into a live persisted progress line on the task card.
replace_once(
    "        dedaText(\n"
    "          'اقطع مسافة 1 كم أثناء رحلة فعلية باستخدام DEDA',\n"
    "          'Travel 1 km during a real trip using DEDA',\n"
    "        ),\n",
    "        _longTripProgressText(),\n",
    'long trip dynamic subtitle',
)

# Extend the 100253 route-page accumulator with timestamp-aware plausibility
# filtering and persistence throttling. This keeps real highway movement valid
# even if Android delays a GPS callback, while rejecting impossible teleports.
replace_once(
    '  LatLng? _dailyTaskTripLastPoint;\n'
    '  double _dailyTaskTripDistanceMeters = 0;\n'
    '  bool _dailyTaskTripReported = false;\n',
    '  LatLng? _dailyTaskTripLastPoint;\n'
    '  DateTime? _dailyTaskTripLastFixAt;\n'
    '  double _dailyTaskTripDistanceMeters = 0;\n'
    '  double _dailyTaskTripLastSavedMeters = 0;\n'
    '  bool _dailyTaskTripReported = false;\n',
    'trip progress tracker fields',
)

replace_once(
    '      _dailyTaskTripLastPoint = null;\n'
    '      _dailyTaskTripDistanceMeters = 0;\n'
    '      _dailyTaskTripReported = false;\n',
    '      _dailyTaskTripLastPoint = null;\n'
    '      _dailyTaskTripLastFixAt = null;\n'
    '      _dailyTaskTripDistanceMeters = 0;\n'
    '      _dailyTaskTripLastSavedMeters = 0;\n'
    '      _dailyTaskTripReported = false;\n'
    '      unawaited(DedaLongTripProgress.resetForNewTrip());\n',
    'trip progress reset',
)

tracker_pattern = re.compile(
    r'(?P<indent>[ \t]+)final taskGpsAccurate = position\.accuracy\.isFinite &&\n'
    r'(?P=indent)    position\.accuracy <= 30;\n'
    r'(?P=indent)if \(taskGpsAccurate\) \{\n'
    r'(?P=indent)  final taskPrevious = _dailyTaskTripLastPoint;\n'
    r'(?P=indent)  if \(taskPrevious != null\) \{\n'
    r'(?P=indent)    final taskSegmentMeters = _metersBetween\(taskPrevious, current\);\n'
    r'(?P=indent)    if \(taskSegmentMeters >= 1 && taskSegmentMeters <= 200\) \{\n'
    r'(?P=indent)      _dailyTaskTripDistanceMeters \+= taskSegmentMeters;\n'
    r'(?P=indent)    \}\n'
    r'(?P=indent)  \}\n'
    r'(?P=indent)  _dailyTaskTripLastPoint = current;\n'
    r'(?P=indent)\}\n'
)
match = tracker_pattern.search(text)
if match is None:
    raise SystemExit('robust trip tracker: 100253 tracker block not found')
indent = match.group('indent')
replacement = (
    f"{indent}final taskGpsAccurate = position.accuracy.isFinite &&\n"
    f"{indent}    position.accuracy <= 80;\n"
    f"{indent}if (taskGpsAccurate) {{\n"
    f"{indent}  final taskNow = DateTime.now();\n"
    f"{indent}  final taskPrevious = _dailyTaskTripLastPoint;\n"
    f"{indent}  final taskPreviousAt = _dailyTaskTripLastFixAt;\n"
    f"{indent}  if (taskPrevious != null && taskPreviousAt != null) {{\n"
    f"{indent}    final taskSegmentMeters = _metersBetween(taskPrevious, current);\n"
    f"{indent}    final taskElapsedSeconds = math.max(\n"
    f"{indent}      0.5,\n"
    f"{indent}      taskNow.difference(taskPreviousAt).inMilliseconds / 1000.0,\n"
    f"{indent}    );\n"
    f"{indent}    final taskReportedSpeed = position.speed.isFinite && position.speed > 0\n"
    f"{indent}        ? position.speed\n"
    f"{indent}        : 0.0;\n"
    f"{indent}    final taskPlausibleSpeed = math.max(55.0, taskReportedSpeed * 1.8 + 15.0);\n"
    f"{indent}    final taskMaxSegmentMeters = math.min(\n"
    f"{indent}      2000.0,\n"
    f"{indent}      math.max(120.0, taskElapsedSeconds * taskPlausibleSpeed + 100.0),\n"
    f"{indent}    );\n"
    f"{indent}    if (taskSegmentMeters >= 1 && taskSegmentMeters <= taskMaxSegmentMeters) {{\n"
    f"{indent}      _dailyTaskTripDistanceMeters = math.min(\n"
    f"{indent}        1000.0,\n"
    f"{indent}        _dailyTaskTripDistanceMeters + taskSegmentMeters,\n"
    f"{indent}      );\n"
    f"{indent}      if (_dailyTaskTripDistanceMeters >= 1000 ||\n"
    f"{indent}          _dailyTaskTripDistanceMeters - _dailyTaskTripLastSavedMeters >= 20) {{\n"
    f"{indent}        _dailyTaskTripLastSavedMeters = _dailyTaskTripDistanceMeters;\n"
    f"{indent}        unawaited(DedaLongTripProgress.update(_dailyTaskTripDistanceMeters));\n"
    f"{indent}      }}\n"
    f"{indent}    }}\n"
    f"{indent}  }}\n"
    f"{indent}  _dailyTaskTripLastPoint = current;\n"
    f"{indent}  _dailyTaskTripLastFixAt = taskNow;\n"
    f"{indent}}}\n"
)
text = text[:match.start()] + replacement + text[match.end():]

# Make sure persisted progress reaches 1 km before reporting task completion.
completion_marker = '  _dailyTaskTripReported = true;\n'
completion_count = text.count(completion_marker)
if completion_count != 1:
    raise SystemExit(
        f'completion progress marker: expected exactly one match, found {completion_count}'
    )
text = text.replace(
    completion_marker,
    completion_marker + '  unawaited(DedaLongTripProgress.update(1000));\n',
    1,
)

path.write_text(text, encoding='utf-8')
print('Build 100254 long-trip progress and robust 1 km tracking fix applied.')
