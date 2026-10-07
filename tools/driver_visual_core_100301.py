from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100301 — three field-verified navigation corrections only:
# 1) declutter hazard markers (only the active upcoming hazard, briefly),
# 2) bring normal navigation closer,
# 3) make Driver View a real road-ahead composition with correct perspective
#    direction, route-up camera, and real arrow delta.
# Alert detection/voice thresholds, routing/rerouting, GPS stationary filter,
# tasks, ads and admin logic are intentionally untouched.

def replace_between(src, start_token, end_token, replacement, label):
    s=src.find(start_token)
    e=src.find(end_token, s + len(start_token))
    if s<0 or e<0:
        raise SystemExit(f"100301 {label}: boundary missing")
    return src[:s] + replacement + src[e:]

# ------------------------------------------------------------------
# 1) Normal navigation: field test shows 15.0 is still too wide.
# ------------------------------------------------------------------
if t.count("final navigationHomeZoom = 15.0;") != 1:
    raise SystemExit(
        f"100301 normal zoom anchor count {t.count('final navigationHomeZoom = 15.0;')}"
    )
t=t.replace("final navigationHomeZoom = 15.0;",
            "final navigationHomeZoom = 15.8;",1)

# ------------------------------------------------------------------
# 2) Driver camera must keep the route forward/up. 100300's course-up
#    camera can visually tilt the green route away from screen-up.
# ------------------------------------------------------------------
heading_start="  double _navigationCameraHeading() {"
heading_end="  LatLng _navigationCameraTarget("
new_heading=r'''  double _navigationCameraHeading() {
    // Driver View is route-up: the green route owns the screen vertical.
    // The user's real heading remains independent and is shown by the arrow.
    return _routeCameraHeading;
  }

'''
t=replace_between(t,heading_start,heading_end,new_heading,"route-up driver camera")

# The fixed Driver arrow must always show the phone/movement delta against
# the route-up map. Do not force it to 0 at driving speed.
arrow_pattern=re.compile(
    r'''_buildFixedDriverArrow\(\s*_navigationDisplaySpeedMps\s*>=\s*3\.0\s*\?\s*0\.0\s*:\s*navigationArrowAngle,?\s*\)''',
    re.S,
)
t,n=arrow_pattern.subn("_buildFixedDriverArrow(navigationArrowAngle)",t,count=1)
if n!=1:
    raise SystemExit(f"100301 fixed Driver arrow replacement count {n}")

# ------------------------------------------------------------------
# 3) Correct the perspective direction.
# Previous +Z perspective enlarged the distant/top edge.  The negative
# perspective below makes the distant edge narrower, producing the road-
# ahead/horizon effect visible in the approved reference.
# ------------------------------------------------------------------
wrap_start="  Widget _wrapDriverPerspective(Widget child) {"
wrap_end="  Widget _buildFixedDriverArrow(double angle) {"
new_wrap=r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, -0.00055 * amount)
          ..scale(1.0 + 0.28 * amount, 1.0 + 0.14 * amount, 1.0)
          ..rotateX(0.42 * amount);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFDDF3FF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFF5FAF5),
                        amount,
                      )!,
                    ],
                  ),
                ),
              ),
              Transform(
                alignment: Alignment.bottomCenter,
                transformHitTests: true,
                transform: matrix,
                child: mapChild,
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }

'''
t=replace_between(t,wrap_start,wrap_end,new_wrap,"Driver perspective")

# ------------------------------------------------------------------
# 4) Road alerts are temporary navigation information, not fixed map POIs.
# Show only the active upcoming alert, only while it is 35–250m ahead.
# The Road Pulse card/voice logic stays untouched.
# ------------------------------------------------------------------
hazard_comment="      // Road alerts are drawn first so they never cover the live navigation"
destination_marker="      Marker(\n        point: destinationPoint,"
hs=t.find(hazard_comment)
he=t.find(destination_marker,hs)
if hs<0 or he<0:
    raise SystemExit("100301 hazard marker boundaries missing")

new_hazard=r'''      // Road alerts are temporary navigation information, not fixed POIs.
      // Keep the map clean: only the currently selected upcoming alert is
      // shown, and only during the useful approach window. Inside 35 m the
      // Road Pulse card remains visible while the map marker disappears so it
      // cannot cover the live arrow.
      if (tripStarted &&
          _activeHazard != null &&
          _hazardIsUsable(_activeHazard!) &&
          _metersBetween(startPoint, _activeHazard!.location) >= 35 &&
          _metersBetween(startPoint, _activeHazard!.location) <= 250)
        Marker(
          point: _activeHazard!.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showHazardDetails(_activeHazard!),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5).withOpacity(0.97),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFB65A00),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black26),
                ],
              ),
              child: Icon(
                _activeHazard!.icon,
                size: 24,
                color: const Color(0xFFB65A00),
              ),
            ),
          ),
        ),
'''
t=t[:hs]+new_hazard+t[he:]

p.write_text(t)
print("DEDA 100301 field-verified visual navigation corrections applied.")
