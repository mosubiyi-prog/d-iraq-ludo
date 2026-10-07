from pathlib import Path

p=Path("lib/main.dart")
t=p.read_text()

def one(old,new,label):
    global t
    if t.count(old)!=1:
        raise SystemExit(f"100298 {label}: count {t.count(old)}")
    t=t.replace(old,new,1)

one("  bool _navigationCameraReturning = false;\n",
    "  bool _navigationCameraReturning = false;\n  bool _driverViewEnabled = false;\n","state")

old=r'''  LatLng _navigationCameraTarget(
    LatLng current,
    double heading,
    double zoom,
  ) {
    final lookAhead =
        (75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0).toDouble();
    return _pointAlongBearing(current, heading, lookAhead);
  }
'''
new=r'''  double _navigationModeZoom() =>
      _driverViewEnabled ? 15.8 : _navigationHomeZoom.clamp(13.6, 16.2).toDouble();

  LatLng _navigationCameraTarget(
    LatLng current,
    double heading,
    double zoom,
  ) {
    final base = _driverViewEnabled ? 165.0 : 75.0;
    final min = _driverViewEnabled ? 120.0 : 35.0;
    final max = _driverViewEnabled ? 300.0 : 280.0;
    final lookAhead =
        (base * math.pow(2.0, 16.0 - zoom)).clamp(min, max).toDouble();
    return _pointAlongBearing(current, heading, lookAhead);
  }
'''
one(old,new,"camera target")
z="_navigationHomeZoom.clamp(13.6, 16.2).toDouble()"
if t.count(z)!=4:
    raise SystemExit(f"100298 camera zoom owners: expected helper + 3 owners, found {t.count(z)}")
# The first occurrence belongs to _navigationModeZoom() itself and must remain.
# Replace only the three downstream camera-owner uses.
first=t.find(z)
tail=t[first+len(z):]
if tail.count(z)!=3:
    raise SystemExit(f"100298 downstream camera zoom owners: {tail.count(z)}")
t=t[:first+len(z)] + tail.replace(z,"_navigationModeZoom()",3)

anchor="  void _followLivePosition(LatLng current) {\n"
if t.count(anchor)!=1: raise SystemExit("100298 follow anchor")
helpers=r'''  void _toggleDriverView() {
    if (!tripStarted || !mounted) return;
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn();
    setState(() => _driverViewEnabled = !_driverViewEnabled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tripStarted) _startSmoothNavigationReturn();
    });
  }

  Widget _buildDriverViewToggle() {
    final active = _driverViewEnabled;
    return Material(
      color: Colors.transparent,
      elevation: 6,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggleDriverView,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: active
                  ? const [Color(0xFF0E7A61), Color(0xFF064C3F)]
                  : const [Color(0xFF27A77B), Color(0xFF0E6E59)],
            ),
            border: Border.all(
              color: active ? const Color(0xFFB9FFE0) : const Color(0xFFA9E8D2),
              width: 2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(left: 10, top: 11,
                child: Icon(Icons.map_outlined, size: 23,
                  color: active ? Colors.white54 : Colors.white)),
              Positioned(right: 9, bottom: 10,
                child: Icon(Icons.directions_car_filled, size: 25,
                  color: active ? Colors.white : Colors.white70)),
              const Icon(Icons.swap_vert_rounded, size: 17, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.00075 * amount)
          ..scale(1.0 + 0.16 * amount, 1.0 + 0.12 * amount, 1.0)
          ..rotateX(0.28 * amount);
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

  Widget _buildFixedDriverArrow(double angle) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: angle,
        child: Stack(
          alignment: Alignment.center,
          children: const [
            Icon(Icons.navigation, size: 58, color: Colors.white),
            Icon(Icons.navigation, size: 46, color: Color(0xFF087D45)),
          ],
        ),
      ),
    );
  }

'''
t=t.replace(anchor,helpers+anchor,1)

one("                    child: FlutterMap(\n",
    "                    child: _wrapDriverPerspective(FlutterMap(\n","map open")
start=t.find("                    child: _wrapDriverPerspective(FlutterMap(")
close="\n                    ),\n                  ),"
i=t.find(close,start)
if i<0: raise SystemExit("100298 map close")
t=t[:i]+"\n                    )),\n                  ),"+t[i+len(close):]

c=t.find("// Keep one small green heading arrow for the user's start/live position.")
m=t.find("      Marker(",c)
e=t.find("      ),\n    ];",m)
if min(c,m,e)<0: raise SystemExit("100298 arrow marker bounds")
block=t[m:e+len("      ),")]
if "angle: navigationArrowAngle," not in block: raise SystemExit("100298 arrow angle missing")
one_child="        child: Transform.rotate(\n"
if block.count(one_child)!=1: raise SystemExit("100298 arrow child anchor")
block=block.replace(one_child,
    "        child: _driverViewEnabled\n            ? const SizedBox.shrink()\n            : Transform.rotate(\n",1)
t=t[:m]+block+t[e+len("      ),"):]

a="""            if (!(isLandscape && tripStarted) &&
                !(tripStarted && _mapFullscreen))
"""
if t.count(a)!=1: raise SystemExit("100298 map control anchor")
overlay=r'''            if (tripStarted && _driverViewEnabled)
              Positioned.fill(
                child: Align(
                  alignment: Alignment(0, isLandscape ? 0.34 : 0.50),
                  child: _buildFixedDriverArrow(navigationArrowAngle),
                ),
              ),
'''
t=t.replace(a,overlay+a,1)

ps='''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 174 : 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
if t.count(ps)!=1: raise SystemExit(f"100298 portrait speed {t.count(ps)}")
t=t.replace(ps,ps+'''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 244 : 188,
                left: 12,
                child: _buildDriverViewToggle(),
              ),
''',1)
ls='''            if (tripStarted && isLandscape)
              Positioned(
                top: 12,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
if t.count(ls)!=1: raise SystemExit(f"100298 landscape speed {t.count(ls)}")
t=t.replace(ls,ls+'''            if (tripStarted && isLandscape)
              Positioned(
                top: 82,
                left: 12,
                child: _buildDriverViewToggle(),
              ),
''',1)

s=t.find("  Future<void> stopTrip({")
u=t.find("  Widget _buildCompactNavigationBar()",s)
if s<0 or u<0: raise SystemExit("100298 stop bounds")
b=t[s:u]
r="      _navigationCameraReturning = false;\n"
if b.count(r)!=1: raise SystemExit(f"100298 stop reset {b.count(r)}")
b=b.replace(r,r+"      _driverViewEnabled = false;\n",1)
t=t[:s]+b+t[u:]

p.write_text(t)
print("DEDA 100298 isolated Driver View applied.")
