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


# 1) Every completed daily task should show Done and stop reopening its action.
traffic_done_count = text.count('trafficDone')
if traffic_done_count < 3:
    raise SystemExit(
        f'completed task action: expected trafficDone markers, found {traffic_done_count}'
    )
text = text.replace(
    'final trafficDone = index == 6 && completed;',
    'final taskDone = completed;',
    1,
)
text = text.replace('trafficDone', 'taskDone')
if 'trafficDone' in text:
    raise SystemExit('completed task action: trafficDone marker still present')

# 2) Make the last task requirement explicit to the user.
replace_once(
    "'استخدم إحدى خدمات الطريق أثناء رحلتك الطويلة'",
    "'اقطع مسافة 1 كم أثناء رحلة فعلية باستخدام DEDA'",
    'Arabic 1km task subtitle',
)
replace_once(
    "'Use a road service during your long trip'",
    "'Travel 1 km during a real trip using DEDA'",
    'English 1km task subtitle',
)

# 3) Keep an independent GPS accumulator for the current active trip.
replace_once(
    '  double? _liveRemainingMeters;\n',
    '  double? _liveRemainingMeters;\n'
    '  LatLng? _dailyTaskTripLastPoint;\n'
    '  double _dailyTaskTripDistanceMeters = 0;\n'
    '  bool _dailyTaskTripReported = false;\n',
    'trip task fields',
)

# A new navigation session must start its 1 km counter from zero, regardless
# of walking / motorcycle / car / truck mode. The shared startTrip path serves
# all travel modes.
replace_once(
    '      _previousLivePoint = startPoint;\n'
    '      _navigationToolsOpen = false;\n',
    '      _previousLivePoint = startPoint;\n'
    '      _dailyTaskTripLastPoint = null;\n'
    '      _dailyTaskTripDistanceMeters = 0;\n'
    '      _dailyTaskTripReported = false;\n'
    '      _navigationToolsOpen = false;\n',
    'trip task reset on start',
)

# Count only reasonably accurate GPS fixes and discard implausible point jumps.
# 200 m between accepted fixes is intentionally generous for fast vehicles and
# temporary scheduler delays, while still blocking large GPS teleports.
pattern = re.compile(
    r"(?P<indent>\s+)final current = LatLng\(position\.latitude, position\.longitude\);\n"
    r"(?P=indent)final heading =",
)
match = pattern.search(text)
if match is None:
    raise SystemExit('trip task GPS insertion point not found')
indent = match.group('indent')
insert = (
    f"{indent}final current = LatLng(position.latitude, position.longitude);\n"
    f"{indent}final taskGpsAccurate = position.accuracy.isFinite &&\n"
    f"{indent}    position.accuracy <= 30;\n"
    f"{indent}if (taskGpsAccurate) {{\n"
    f"{indent}  final taskPrevious = _dailyTaskTripLastPoint;\n"
    f"{indent}  if (taskPrevious != null) {{\n"
    f"{indent}    final taskSegmentMeters = _metersBetween(taskPrevious, current);\n"
    f"{indent}    if (taskSegmentMeters >= 1 && taskSegmentMeters <= 200) {{\n"
    f"{indent}      _dailyTaskTripDistanceMeters += taskSegmentMeters;\n"
    f"{indent}    }}\n"
    f"{indent}  }}\n"
    f"{indent}  _dailyTaskTripLastPoint = current;\n"
    f"{indent}}}\n"
    f"{indent}if (!_dailyTaskTripReported &&\n"
    f"{indent}    _dailyTaskTripDistanceMeters >= 1000) {{\n"
    f"{indent}  _dailyTaskTripReported = true;\n"
    f"{indent}  unawaited(\n"
    f"{indent}    DedaTaskEngine.recordSuccessfulEvent(\n"
    f"{indent}      DedaTaskEvent.longTripCompleted,\n"
    f"{indent}    ).then<void>((_) {{}}),\n"
    f"{indent}  );\n"
    f"{indent}}}\n"
    f"{indent}final heading ="
)
text = text[:match.start()] + insert + text[match.end():]

path.write_text(text, encoding='utf-8')
print('Daily task Done-state and 1 km trip task fix applied.')
