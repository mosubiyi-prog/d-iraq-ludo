from pathlib import Path

# Full validator for the isolated 100254 branch. It carries forward the stable
# 100253 Done-button invariants while validating the new 1 km progress design.
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
    'broader GPS accuracy': 'position.accuracy <= 80',
    'timestamp-aware segment guard': 'taskMaxSegmentMeters',
    'dynamic speed guard': 'taskPlausibleSpeed',
    '1 km threshold': '_dailyTaskTripDistanceMeters >= 1000',
    'progress persistence': 'DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)',
    'completion persistence': 'DedaLongTripProgress.update(1000)',
    'task completion event': 'DedaTaskEvent.longTripCompleted',
}

for label, marker in required.items():
    if marker not in text:
        raise SystemExit(f'Missing {label}: {marker}')

forbidden = {
    'legacy traffic-only Done logic': 'trafficDone',
    'old strict GPS accuracy': 'position.accuracy <= 30',
    'old fixed 200m segment ceiling': 'taskSegmentMeters <= 200',
    'old long trip subtitle': 'استخدم إحدى خدمات الطريق أثناء رحلتك الطويلة',
}
for label, marker in forbidden.items():
    if marker in text:
        raise SystemExit(f'Forbidden {label} is still present: {marker}')

# Keep the tracker transport-mode independent exactly as in the successful
# 100253 design; walking, motorcycle, car and truck all share the same GPS path.
start = text.find('final taskGpsAccurate = position.accuracy.isFinite')
end = text.find('DedaTaskEvent.longTripCompleted', start)
if start < 0 or end < 0:
    raise SystemExit('Could not locate the final trip tracker block')
tracker = text[start:end]
if 'widget.travelMode' in tracker or 'DedaTravelMode.' in tracker:
    raise SystemExit('Trip tracker must remain independent of travel mode')

if text.count('_dailyTaskTripDistanceMeters = 0;') < 2:
    raise SystemExit('Trip distance counter is not reset at trip start')
if text.count('_dailyTaskTripReported = false;') < 2:
    raise SystemExit('Trip completion flag is not reset at trip start')
if text.count('_dailyTaskTripLastFixAt = null;') != 1:
    raise SystemExit('Trip timestamp tracker is not reset exactly once at trip start')

print('Build 100254 Done-state + robust 1 km progress validation passed.')
