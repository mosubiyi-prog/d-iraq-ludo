from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old_settings = """    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
"""

new_settings = """    // Navigation needs frequent foreground fixes. The generic Android
    // location settings may deliver fixes several seconds apart, which makes
    // the camera stop and then catch up in a visible jump. Request a tighter
    // cadence only while an active trip is running.
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(milliseconds: 500),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
"""

if text.count(old_settings) != 1:
    raise SystemExit(
        f'Expected exactly one navigation LocationSettings block, found {text.count(old_settings)}'
    )
text = text.replace(old_settings, new_settings, 1)

old_animation = """    // Keep the marker moving continuously between GPS fixes. A ~60 Hz
    // interpolation avoids visible jumps while restarting cleanly from the
    // current displayed point when a newer fix arrives.
    final durationMs =
        (560 + math.min(distance, 30) * 16).round().clamp(560, 1050);
    const frameMs = 16;
"""

new_animation = """    // Keep the marker and camera moving continuously between GPS fixes.
    // Navigation fixes are requested at a high cadence; a near-one-second
    // linear bridge prevents the ease-in/ease-out stop that was visible as
    // "freeze for a few seconds, then jump" during real driving.
    final durationMs =
        (620 + math.min(distance, 30) * 14).round().clamp(620, 1080);
    const frameMs = 16;
"""

if text.count(old_animation) != 1:
    raise SystemExit(
        f'Expected exactly one navigation animation block, found {text.count(old_animation)}'
    )
text = text.replace(old_animation, new_animation, 1)

old_curve = """        final linear = (frame / totalFrames).clamp(0.0, 1.0);
        final eased = Curves.easeInOutCubic.transform(linear);
        final point = LatLng(
"""

new_curve = """        final linear = (frame / totalFrames).clamp(0.0, 1.0);
        // Linear interpolation avoids decelerating to zero at every GPS fix.
        final eased = linear;
        final point = LatLng(
"""

if text.count(old_curve) != 1:
    raise SystemExit(
        f'Expected exactly one navigation interpolation curve, found {text.count(old_curve)}'
    )
text = text.replace(old_curve, new_curve, 1)

path.write_text(text, encoding='utf-8')
print('Applied DEDA navigation smooth-follow patch successfully.')
