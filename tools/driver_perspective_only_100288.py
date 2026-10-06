from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100288 - focused driver perspective only.
# Keep all 100287 navigation logic intact and add only the visual perspective
# transform for Driver View. The transform animates even while stationary.

helper_anchor = "  void _followLivePosition(LatLng current) {\n"
if helper_anchor not in text:
    raise SystemExit("100288: follow helper anchor missing")

helper = r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        // A flat navigation map becomes a road-ahead perspective immediately,
        // even while the vehicle is stationary. The bottom of the map stays
        // visually close while the upper area recedes like a driver's view.
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.00118 * amount)
          ..scale(
            1.0 + (0.34 * amount),
            1.0 + (0.34 * amount),
            1.0,
          )
          ..rotateX(0.56 * amount);
        return Transform(
          alignment: Alignment.bottomCenter,
          transformHitTests: true,
          transform: matrix,
          child: mapChild,
        );
      },
      child: child,
    );
  }

'''
text = text.replace(helper_anchor, helper + helper_anchor, 1)

# Strengthen forward framing only while Driver View is enabled so the live
# arrow sits lower and more road is visible ahead. Normal mode is untouched.
old_mode_zoom = '''  double _navigationModeZoom(double currentZoom) {
    if (_driverViewEnabled) {
      return currentZoom.clamp(16.0, 17.0).toDouble();
    }
'''
new_mode_zoom = '''  double _navigationModeZoom(double currentZoom) {
    if (_driverViewEnabled) {
      return currentZoom.clamp(16.2, 17.2).toDouble();
    }
'''
if old_mode_zoom not in text:
    raise SystemExit("100288: driver zoom anchor missing")
text = text.replace(old_mode_zoom, new_mode_zoom, 1)

old_lookahead = '''    final baseMeters = _driverViewEnabled ? 118.0 : 75.0;
    final minMeters = _driverViewEnabled ? 58.0 : 35.0;
    final maxMeters = _driverViewEnabled ? 360.0 : 280.0;
'''
new_lookahead = '''    final baseMeters = _driverViewEnabled ? 155.0 : 75.0;
    final minMeters = _driverViewEnabled ? 80.0 : 35.0;
    final maxMeters = _driverViewEnabled ? 480.0 : 280.0;
'''
if old_lookahead not in text:
    raise SystemExit("100288: driver look-ahead anchor missing")
text = text.replace(old_lookahead, new_lookahead, 1)

# Wrap only the map canvas. Navigation cards and controls remain perfectly flat
# and readable above it. Touch hit-testing is preserved by Transform.
map_start = text.find("                    child: FlutterMap(")
if map_start < 0:
    raise SystemExit("100288: FlutterMap anchor missing")
text = text[:map_start] + text[map_start:].replace(
    "                    child: FlutterMap(",
    "                    child: _wrapDriverPerspective(FlutterMap(",
    1,
)

# Close the wrapper directly where FlutterMap closes, before ClipRRect closes.
map_start = text.find("                    child: _wrapDriverPerspective(FlutterMap(")
map_close = text.find("\n                    ),\n                  ),", map_start)
if map_close < 0:
    raise SystemExit("100288: FlutterMap closing anchor missing")
text = (
    text[:map_close]
    + "\n                    )),\n                  ),"
    + text[map_close + len("\n                    ),\n                  ),"):]
)

path.write_text(text)
print("DEDA 100288 focused driver perspective applied.")
