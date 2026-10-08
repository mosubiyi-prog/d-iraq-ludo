from pathlib import Path
import re

# DEDA 100310 — small and isolated changes ON TOP OF EXACT 100303.
# 1) Remove blue "sky" gradient behind Driver View (not a raster image).
# 2) Align fixed arrow's pixel anchor with live green-route camera target.
# 3) Light perspective measurement adjustment; NO routing/GPS/hazard changes.
p = Path("lib/main.dart")
t = p.read_text()

def replace_once(old, new, label):
    global t
    count = t.count(old)
    if count != 1:
        raise SystemExit(f"100310 {label}: expected one anchor, got {count}")
    t = t.replace(old, new, 1)

# Remove ONLY the artificial sky backdrop inside _wrapDriverPerspective.
wrap_start = t.find("  Widget _wrapDriverPerspective(Widget child) {")
wrap_end = t.find("  Widget _buildFixedDriverArrow(double angle) {", wrap_start)
if wrap_start < 0 or wrap_end < 0:
    raise SystemExit("100310 perspective wrapper boundaries missing")
sky_start = t.find("              DecoratedBox(", wrap_start, wrap_end)
map_start = t.find("              Transform(", sky_start, wrap_end)
if sky_start < 0 or map_start < 0:
    raise SystemExit("100310 sky/map layer boundaries missing")
sky_block = t[sky_start:map_start]
if sky_block.count("const Color(0xFFDDF3FF)") != 1 or "gradient: LinearGradient(" not in sky_block:
    raise SystemExit("100310 artificial sky gradient differs from 100303")
# Plain neutral background is used for uncovered projection margins.
# In particular: no painted blue horizon, no fake sky, no extra map layer.
t = t[:sky_start] + "              const ColoredBox(color: Color(0xFFF5FAF5)),\n" + t[map_start:]

# Do not alter geographic polylines or Google/OSM position sources.
# Adjust just the projection gently to avoid exaggerated bending.
replace_once(
    "setEntry(3, 2, -0.00070 * amount)",
    "setEntry(3, 2, -0.00065 * amount)",
    "mild perspective",
)
replace_once(
    "scale(1.0 + 0.32 * amount, 1.0 + 0.17 * amount, 1.0)",
    "scale(1.0 + 0.30 * amount, 1.0 + 0.16 * amount, 1.0)",
    "road width",
)
replace_once(
    "rotateX(0.50 * amount)",
    "rotateX(0.48 * amount)",
    "road tilt",
)

# 100303 keeps the green route anchored at _displayPosition. The pixel lead
# should equal the fixed arrow's relative screen position in BOTH orientations.
# Portrait 70% from top = Alignment.y 0.40; landscape 62% = 0.24.
replace_once(
    "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)",
    "alignment: Alignment(0, isLandscape ? 0.24 : 0.40)",
    "driver arrow screen anchor",
)

# The extra speed lookahead and mandatory 140m minimum displaced the line
# from the overlay arrow, especially on a landscape/small viewport. Base it
# instead on actual screen pixels and Mercator m/px. Keep 100303 route-up
# camera and zoom untouched.
# Dart format may merge/reflow this expression, so use a tightly scoped
# multi-line pattern rather than a literal whitespace-dependent anchor.
speed_pattern = re.compile(
    r"      final speedMps\s*=\s*_navigationDisplaySpeedMps\.clamp\(0\.0,\s*45\.0\)\.toDouble\(\);\s*(?=      final latitudeScale)"
)
t, n = speed_pattern.subn("", t, count=1)
if n != 1:
    raise SystemExit(f"100310 speed lead anchor count {n}")

lookahead_pattern = re.compile(
    r"      final lookAhead\s*=\s*\(metersPerPixel\s*\*\s*desiredPixels\s*\+\s*speedMps\s*\*\s*1\.2\)\s*\.clamp\(140\.0,\s*520\.0\)\s*\.toDouble\(\);"
)
t, n = lookahead_pattern.subn(
    "      final lookAhead = (metersPerPixel * desiredPixels)\n"
    "          .clamp(35.0, 520.0)\n"
    "          .toDouble();",
    t, count=1
)
if n != 1:
    raise SystemExit(f"100310 screen-space lead anchor count {n}")

p.write_text(t)

# Acceptance: ensure sky removed and hard untouched invariants still exist.
checks = {
    "no fake sky in Driver View":
        "const Color(0xFFDDF3FF)" not in t
        and "const ColoredBox(color: Color(0xFFF5FAF5))" in t,
    "live route anchor retained":
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t,
    "arrow on route target":
        "alignment: Alignment(0, isLandscape ? 0.24 : 0.40)" in t
        and "media.height * (isLandscape ? 0.12 : 0.20)" in t
        and "(metersPerPixel * desiredPixels)" in t,
    "moderate perspective":
        "setEntry(3, 2, -0.00065 * amount)" in t
        and "rotateX(0.48 * amount)" in t,
    "route-up preserved":
        "double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t,
    "heading delta preserved":
        "_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "normal navigation zoom preserved":
        "final navigationHomeZoom = 15.8;" in t,
    "normal camera preserved":
        "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "stationary GPS filter preserved":
        "final requiredCandidates = isWalking ? 2 : 3;" in t,
    "rerouting preserved":
        "best.type == 'detour'" in t and "bestDistance <= 900" in t,
    "warnings preserved":
        "if (_isNeighborhoodBump(hazard)) return 50.0;" in t,
    "hazard speech preserved":
        "_spokenHazardIds.add(best.id);" in t,
    "10-second free control preserved":
        "Timer(const Duration(seconds: 10)" in t,
    "trip task preserved":
        "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
missing = [name for name, ok in checks.items() if not ok]
if missing:
    raise SystemExit("100310 post-patch validation FAILED: " + "; ".join(missing))
print("DEDA 100310: sky removed, fixed arrow/green route alignment corrected, mild perspective verified.")
