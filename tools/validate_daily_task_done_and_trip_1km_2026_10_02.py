from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

checks = {
    'all completed tasks use taskDone': 'final taskDone = completed;',
    'completed action label': "label: taskDone ? dedaText('تم', 'Done') : action",
    'completed action disabled': 'onTap: taskDone ? null : () => _openTask(index)',
    'completed card disabled': 'onTap: taskDone ? null : () => _openTask(index)',
    'Arabic 1 km subtitle': 'اقطع مسافة 1 كم أثناء رحلة فعلية باستخدام DEDA',
    'English 1 km subtitle': 'Travel 1 km during a real trip using DEDA',
    'trip last point field': 'LatLng? _dailyTaskTripLastPoint;',
    'trip distance field': 'double _dailyTaskTripDistanceMeters = 0;',
    'trip completion flag': 'bool _dailyTaskTripReported = false;',
    'GPS accuracy guard': 'position.accuracy <= 30',
    'GPS jump guard': 'taskSegmentMeters <= 200',
    '1 km threshold': '_dailyTaskTripDistanceMeters >= 1000',
    'long trip event': 'DedaTaskEvent.longTripCompleted',
}

for label, needle in checks.items():
    if needle not in text:
        raise SystemExit(f'Missing {label}: {needle}')

if 'trafficDone' in text:
    raise SystemExit('Legacy traffic-only Done logic is still present')

# The 1 km tracker must not branch on a specific travel mode. It is inserted in
# the shared navigation GPS stream, so walking, motorcycle, car and truck all
# use the same distance rule.
tracker_start = text.find('final taskGpsAccurate = position.accuracy.isFinite')
tracker_end = text.find('final heading =', tracker_start)
if tracker_start < 0 or tracker_end < 0:
    raise SystemExit('Could not locate trip tracker block')
tracker = text[tracker_start:tracker_end]
if 'widget.travelMode' in tracker or 'DedaTravelMode.' in tracker:
    raise SystemExit('Trip tracker must remain transport-mode independent')

if text.count('_dailyTaskTripDistanceMeters = 0;') < 2:
    raise SystemExit('Trip distance counter is not reset at trip start')
if text.count('_dailyTaskTripReported = false;') < 2:
    raise SystemExit('Trip completion flag is not reset at trip start')

print('Daily task Done-state and 1 km all-transport trip validation passed.')
