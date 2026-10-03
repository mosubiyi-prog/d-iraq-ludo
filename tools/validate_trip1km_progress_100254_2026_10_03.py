from pathlib import Path

# Trigger/build validator for the isolated 100254 branch only.
text = Path('lib/main.dart').read_text(encoding='utf-8')

required = {
    'shared progress helper': 'class DedaLongTripProgress',
    'daily progress key': "deda_long_trip_progress_m_v1",
    'daily progress field': 'double _longTripProgressMeters = 0;',
    'dynamic task subtitle': '_longTripProgressText(),',
    'travelled Arabic label': 'قطعت $travelledKm كم • المتبقي ${remaining.round()} متر',
    'trip last fix field': 'DateTime? _dailyTaskTripLastFixAt;',
    'trip saved progress field': 'double _dailyTaskTripLastSavedMeters = 0;',
    'trip reset persistence': 'DedaLongTripProgress.resetForNewTrip()',
    'broader GPS accuracy': 'position.accuracy <= 80',
    'timestamp-aware segment guard': 'taskMaxSegmentMeters',
    'dynamic speed guard': 'taskPlausibleSpeed',
    'progress persistence': 'DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)',
    'completion persistence': 'DedaLongTripProgress.update(1000)',
    'task completion event': 'DedaTaskEvent.longTripCompleted',
}

for label, marker in required.items():
    if marker not in text:
        raise SystemExit(f'Missing {label}: {marker}')

forbidden = {
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

print('Build 100254 trip progress validation passed.')
