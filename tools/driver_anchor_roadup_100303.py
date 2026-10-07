from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100303 — Driver View anchor/road-up correction only.
# Field target:
#   * live green route begins at the user's displayed GPS position in Driver View,
#   * camera is centered ahead far enough that that GPS point sits near the
#     fixed lower-center arrow,
#   * local route heading owns map rotation so the near route rises vertically,
#   * perspective is a little stronger and slower, without touching normal mode.
# 100302 bump logic, routing/rerouting, stationary filter and normal navigation
# are intentionally untouched.

def replace_between(src, start_token, end_token, replacement, label):
    s=src.find(start_token)
    e=src.find(end_token, s + len(start_token))
    if s<0 or e<0:
        raise SystemExit(f"100303 {label}: boundary missing")
    return src[:s] + replacement + src[e:]

# 1) Driver-only route display starts from the real displayed position.
# Normal mode keeps the proven fixed route origin from 100297.
old_current="      final current = _lastRouteOrigin ?? startPoint;"
new_current="""      final current = _driverViewEnabled
          ? (_displayPosition ?? startPoint)
          : (_lastRouteOrigin ?? startPoint);"""
if t.count(old_current)!=1:
    raise SystemExit(f"100303 visible-route current anchor count {t.count(old_current)}")
t=t.replace(old_current,new_current,1)

# 2) Keep Driver View close, but don't use zoom as the arrow-placement trick.
# Camera lead below handles arrow/route attachment directly.
zoom_pattern=re.compile(
    r"return \(16\.42 - speedKmh \* 0\.0052\)\.clamp\(15\.80, 16\.42\)\.toDouble\(\);"
)
t,n=zoom_pattern.subn(
    "return (16.58 - speedKmh * 0.0052).clamp(15.95, 16.58).toDouble();",
    t,
    count=1,
)
if n!=1:
    raise SystemExit(f"100303 driver zoom replacement count {n}")

# 3) Put the geographic current point near the fixed arrow on every screen.
# This is based on screen pixels + map metres-per-pixel, not a guessed static
# metre value. Normal mode retains its original 75m/zoom formula exactly.
target_start="  LatLng _navigationCameraTarget("
target_end="  void _cancelNavigationCameraReturn()"
new_target=r'''  LatLng _navigationCameraTarget(
    LatLng current,
    double heading,
    double zoom,
  ) {
    if (_driverViewEnabled) {
      final speedMps =
          _navigationDisplaySpeedMps.clamp(0.0, 45.0).toDouble();
      final latitudeScale =
          math.cos(current.latitude * math.pi / 180).abs().clamp(0.25, 1.0);
      final metersPerPixel =
          156543.03392 * latitudeScale / math.pow(2.0, zoom);
      final media = MediaQuery.sizeOf(context);
      final isLandscape = media.width > media.height;
      final desiredPixels =
          media.height * (isLandscape ? 0.12 : 0.20);
      final lookAhead =
          (metersPerPixel * desiredPixels + speedMps * 1.2)
              .clamp(140.0, 520.0)
              .toDouble();
      return _pointAlongBearing(current, heading, lookAhead);
    }

    final lookAhead =
        (75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0).toDouble();
    return _pointAlongBearing(current, heading, lookAhead);
  }

'''
t=replace_between(t,target_start,target_end,new_target,"screen-anchored camera target")

# 4) Strengthen only the Driver perspective enough to make the near road
# broad and the distant road narrower, with a calm 1.6s mode transition.
for old,new,label in [
    ("duration: const Duration(milliseconds: 1000),",
     "duration: const Duration(milliseconds: 1600),",
     "transition"),
    ("setEntry(3, 2, -0.00055 * amount)",
     "setEntry(3, 2, -0.00070 * amount)",
     "perspective"),
    ("scale(1.0 + 0.28 * amount, 1.0 + 0.14 * amount, 1.0)",
     "scale(1.0 + 0.32 * amount, 1.0 + 0.17 * amount, 1.0)",
     "scale"),
    ("rotateX(0.42 * amount)",
     "rotateX(0.50 * amount)",
     "tilt"),
]:
    if t.count(old)!=1:
        raise SystemExit(f"100303 {label} anchor count {t.count(old)}")
    t=t.replace(old,new,1)

# 5) Fixed Driver arrow sits lower-center but slightly closer to the geographic
# anchor than 100301. Its angle still shows the real phone/movement delta.
old_align="alignment: Alignment(0, isLandscape ? 0.38 : 0.56)"
new_align="alignment: Alignment(0, isLandscape ? 0.38 : 0.46)"
if t.count(old_align)!=1:
    raise SystemExit(f"100303 driver arrow alignment count {t.count(old_align)}")
t=t.replace(old_align,new_align,1)

# Route-up ownership stays explicit; this is the vertical-road invariant.
if "double _navigationCameraHeading()" not in t or "return _routeCameraHeading;" not in t:
    raise SystemExit("100303 route-up camera invariant missing")
if "_buildFixedDriverArrow(navigationArrowAngle)" not in t:
    raise SystemExit("100303 real Driver arrow angle invariant missing")

p.write_text(t)
print("DEDA 100303 Driver View anchor/road-up correction applied.")
