from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

# 1) Request frequent fixes, but leave enough time for each visual movement to finish.
old_settings = """    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(milliseconds: 500),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          );
"""
new_settings = """    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
            intervalDuration: const Duration(milliseconds: 700),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
          );
"""
if text.count(old_settings) != 1:
    raise SystemExit(f'Expected navigation location settings once, found {text.count(old_settings)}')
text = text.replace(old_settings, new_settings, 1)

# 2) The Build 227 animation could last longer than the GPS interval. Shorten it
# so it completes before the next expected fix. Snap only after an abnormally
# large gap so the camera never trails far behind the real vehicle position.
old_animation = """    // Keep the marker and camera moving continuously between GPS fixes.
    // Navigation fixes are requested at a high cadence; a near-one-second
    // linear bridge prevents the ease-in/ease-out stop that was visible as
    // \"freeze for a few seconds, then jump\" during real driving.
    final durationMs =
        (620 + math.min(distance, 30) * 14).round().clamp(620, 1080);
    const frameMs = 16;
    final totalFrames = math.max(1, (durationMs / frameMs).ceil());
    var frame = 0;

    _positionAnimationTimer = Timer.periodic(
"""
new_animation = """    // Build 227 could restart a 620-1080 ms animation every ~500 ms,
    // keeping the displayed marker/camera permanently behind the real GPS fix.
    // Finish each bridge well before the next expected fix. If Android delivers
    // a very large jump after a delayed fix, snap to the real point instead of
    // visually dragging the vehicle through an outdated position.
    if (distance >= 65) {
      setState(() {
        _displayPosition = target;
        final movingByGps = (livePosition?.speed ?? 0) >= 0.8;
        if (movingByGps || !_compassHeadingIsFresh) {
          _displayHeading = targetHeading % 360;
        }
      });
      if (tripStarted) _followLivePosition(target);
      return;
    }

    final durationMs =
        (190 + math.min(distance, 22) * 5).round().clamp(190, 300);
    const frameMs = 16;
    final totalFrames = math.max(1, (durationMs / frameMs).ceil());
    var frame = 0;

    _positionAnimationTimer = Timer.periodic(
"""
if text.count(old_animation) != 1:
    raise SystemExit(f'Expected Build 227 animation block once, found {text.count(old_animation)}')
text = text.replace(old_animation, new_animation, 1)

# 3) Re-route sooner in urban driving, while requiring good accuracy and two
# consecutive off-route fixes to avoid reacting to one noisy GPS sample.
old_accuracy = """        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 40;
        final offRoute = currentRoute != null &&
            !currentRoute.isDirectFallback &&
            _distanceToRoute(current) >= 90;
"""
new_accuracy = """        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 30;
        final offRoute = currentRoute != null &&
            !currentRoute.isDirectFallback &&
            _distanceToRoute(current) >= 45;
"""
if text.count(old_accuracy) != 1:
    raise SystemExit(f'Expected off-route accuracy block once, found {text.count(old_accuracy)}')
text = text.replace(old_accuracy, new_accuracy, 1)

old_reroute = """        final rerouteAllowed = _lastRerouteAttemptAt == null ||
            now.difference(_lastRerouteAttemptAt!) >=
                const Duration(seconds: 20);
        if (_offRouteFixes >= 3 && rerouteAllowed && !isRerouting) {
"""
new_reroute = """        final rerouteAllowed = _lastRerouteAttemptAt == null ||
            now.difference(_lastRerouteAttemptAt!) >=
                const Duration(seconds: 10);
        if (_offRouteFixes >= 2 && rerouteAllowed && !isRerouting) {
"""
if text.count(old_reroute) != 1:
    raise SystemExit(f'Expected reroute threshold block once, found {text.count(old_reroute)}')
text = text.replace(old_reroute, new_reroute, 1)

path.write_text(text, encoding='utf-8')
print('Applied Build 227 navigation hotfix successfully.')
