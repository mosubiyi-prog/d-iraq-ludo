from pathlib import Path

# Full validator for the isolated 100254 branch. It carries forward the stable
# 100253 Done-button invariants while validating only the new 1 km tracker
# block for the changed GPS rules; other GPS features are intentionally left
# untouched and may keep their own accuracy thresholds.
text = Path('lib/main.dart').read_text(encoding='utf-8')

required = {
    'all completed tasks use taskDone': 'final taskDone = completed;',
    'completed action label': "label: taskDone ? dedaText('تم', 'Done') : action",
    'completed action disabled': 'onTap: taskDone ? null : () => _openTask(index)',
    'shared progress helper': 'class DedaLongTripProgress',
    'daily progress key': 'deda_long_trip_progress_m_v1',
    'daily progress field': 'double _longTripProgressMeters = 0;',
    'dynamic task subtitle': '_longTripProgressText(),',
    'travelled Arabic label': 'قطعت $travelledKm كم • المتبقي ${remaining.round()} متر',
    'trip last point field': 'LatLng? _dailyTaskTripLastPoint;',
    'trip last fix field': 'DateTime? _dailyTaskTripLastFixAt;',
    'trip distance field': 'double _dailyTaskTripDistanceMeters = 0;',
    'trip saved progress field': 'double _dailyTaskTripLastSavedMeters = 0;',
    'trip completion flag': 'bool _dailyTaskTripReported = false;',
    'trip reset persistence': 'DedaLongTripProgress.resetForNewTrip()',
    '1 km threshold': '_dailyTaskTripDistanceMeters >= 1000',
    'progress persistence': 'DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)',
    'completion persistence': 'DedaLongTripProgress.update(1000)',
    'task completion event': 'DedaTaskEvent.longTripCompleted',
}

for label, marker in required.items():
    if marker not in text:
        raise SystemExit(f'Missing {label}: {marker}')

if 'trafficDone' in text:
    raise SystemExit('Legacy traffic-only Done logic is still present')
if 'استخدم إحدى خدمات الطريق أثناء رحلتك الطويلة' in text:
    raise SystemExit('Old long trip subtitle is still present')

# Inspect only the actual long-trip tracker. Other map/location code can have
# independent thresholds and must not be modified by this targeted fix.
start = text.find('final taskGpsAccurate = position.accuracy.isFinite')
end = text.find('DedaTaskEvent.longTripCompleted', start)
if start < 0 or end < 0:
    raise SystemExit('Could not locate the final trip tracker block')
tracker = text[start:end]

tracker_required = {
    'broader tracker GPS accuracy': 'position.accuracy <= 80',
    'timestamp-aware segment guard': 'taskMaxSegmentMeters',
    'dynamic speed guard': 'taskPlausibleSpeed',
}
for label, marker in tracker_required.items():
    if marker not in tracker:
        raise SystemExit(f'Missing {label}: {marker}')

tracker_forbidden = {
    'old tracker GPS accuracy': 'position.accuracy <= 30',
    'old fixed 200m segment ceiling': 'taskSegmentMeters <= 200',
}
for label, marker in tracker_forbidden.items():
    if marker in tracker:
        raise SystemExit(f'Forbidden {label} is still present in tracker: {marker}')

if 'widget.travelMode' in tracker or 'DedaTravelMode.' in tracker:
    raise SystemExit('Trip tracker must remain independent of travel mode')

if text.count('_dailyTaskTripDistanceMeters = 0;') < 2:
    raise SystemExit('Trip distance counter is not reset at trip start')
if text.count('_dailyTaskTripReported = false;') < 2:
    raise SystemExit('Trip completion flag is not reset at trip start')
if text.count('_dailyTaskTripLastFixAt = null;') != 1:
    raise SystemExit('Trip timestamp tracker is not reset exactly once at trip start')

print('Build 100254 Done-state + robust 1 km progress validation passed.')
