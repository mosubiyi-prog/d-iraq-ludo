from pathlib import Path

p = Path("lib/deda_driver_map.dart")
t = p.read_text()

# DEDA 100309 — free vector Driver test only.
# Keep the 100308 true-pitch MapLibre renderer and all DEDA navigation logic,
# but:
#   1) remove the artificial sky completely,
#   2) use OpenFreeMap Liberty vector style (free, no API key),
#   3) let the vector map fill the full Driver viewport.
# No GPS/reroute/hazard/voice/task/normal-map behavior is changed here.

style_start = "  static const String _osmStyle = '''"
style_end = "  ml.LatLng _ml(ll.LatLng p)"
s = t.find(style_start)
e = t.find(style_end, s)
if s < 0 or e < 0:
    raise SystemExit("100309 style block boundaries missing")

new_style = """  static const String _driverStyle =
      ml.MapLibreStyles.openfreemapLiberty;

"""
t = t[:s] + new_style + t[e:]

build_start = "  @override\n  Widget build(BuildContext context) {"
s = t.find(build_start)
if s < 0:
    raise SystemExit("100309 build method start missing")

# deda_driver_map.dart contains only this widget class; replace the old
# sky/Positioned layout from build() to the class closing brace.
last_close = t.rfind("\n}")
if last_close < s:
    raise SystemExit("100309 class closing brace missing")

new_build = r'''  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => widget.onMapGesture(),
          child: ml.MapLibreMap(
            styleString: _driverStyle,
            initialCameraPosition: _cameraPosition(),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: false,
            compassEnabled: false,
            logoEnabled: false,
          ),
        ),
        const Positioned(
          right: 6,
          bottom: 4,
          child: IgnorePointer(
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF4D5A61),
                backgroundColor: Color(0xAAFFFFFF),
              ),
            ),
          ),
        ),
      ],
    );
  }
'''
t = t[:s] + new_build + t[last_close:]

# Safety: 100309 must contain no artificial sky geometry or raster OSM tiles.
for stale in (
    "skyFraction",
    "skyHeight",
    "DEDA Driver OSM",
    "tile.openstreetmap.org/{z}/{x}/{y}.png",
    "Color(0xFF8FD2FF)",
    "Color(0xFFCBEAFF)",
    "Color(0xFFF7FBFF)",
):
    if stale in t:
        raise SystemExit("100309 stale sky/raster token remains: " + stale)

required = [
    "ml.MapLibreStyles.openfreemapLiberty",
    "tilt: _driverTilt",
    "bearing: (widget.headingDegrees + 360) % 360",
    "controller.addLine(",
    "lineColor: '#22D866'",
    "onPointerDown: (_) => widget.onMapGesture()",
]
missing = [x for x in required if x not in t]
if missing:
    raise SystemExit("100309 required Driver invariant missing: " + "; ".join(missing))

p.write_text(t)
print("DEDA 100309 free vector Driver test applied.")
