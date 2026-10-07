from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100299 — visual finish for Driver View only.
# Goal: make the road-ahead perspective immediately obvious and readable,
# while preserving every proven 100297/100298 navigation behavior underneath.

def sub_once(pattern, repl, label, flags=0):
    global t
    t2,n=re.subn(pattern,repl,t,count=1,flags=flags)
    if n!=1:
        raise SystemExit(f"100299 {label}: count {n}")
    t=t2

# 1) Stronger but controlled road-ahead perspective.
sub_once(r"setEntry\(3, 2, 0\.00075 \* amount\)",
         "setEntry(3, 2, 0.00100 * amount)",
         "perspective depth")
sub_once(r"scale\(1\.0 \+ 0\.16 \* amount, 1\.0 \+ 0\.12 \* amount, 1\.0\)",
         "scale(1.0 + 0.28 * amount, 1.0 + 0.20 * amount, 1.0)",
         "perspective overscan")
sub_once(r"rotateX\(0\.28 \* amount\)",
         "rotateX(0.42 * amount)",
         "perspective tilt")

# 2) Driver framing only: closer and farther forward.
sub_once(r"_driverViewEnabled\s*\?\s*15\.8\s*:",
         "_driverViewEnabled ? 16.0 :",
         "driver zoom")
sub_once(r"final\s+base\s*=\s*_driverViewEnabled\s*\?\s*165\.0\s*:\s*75\.0\s*;",
         "final base = _driverViewEnabled ? 220.0 : 75.0;",
         "driver lookahead base")
sub_once(r"final\s+min\s*=\s*_driverViewEnabled\s*\?\s*120\.0\s*:\s*35\.0\s*;",
         "final min = _driverViewEnabled ? 150.0 : 35.0;",
         "driver lookahead min")
sub_once(r"final\s+max\s*=\s*_driverViewEnabled\s*\?\s*300\.0\s*:\s*280\.0\s*;",
         "final max = _driverViewEnabled ? 360.0 : 280.0;",
         "driver lookahead max")

# 3) In Driver View the vehicle arrow represents forward screen direction.
# Normal 100296 arrow semantics remain untouched outside Driver View.
if t.count("_buildFixedDriverArrow(navigationArrowAngle)") != 1:
    raise SystemExit("100299 fixed driver arrow call missing")
t=t.replace("_buildFixedDriverArrow(navigationArrowAngle)",
            "_buildFixedDriverArrow(0.0)",1)

sub_once(r"alignment:\s*Alignment\(0,\s*isLandscape \? 0\.34 : 0\.50\)",
         "alignment: Alignment(0, isLandscape ? 0.38 : 0.56)",
         "driver arrow position")

# Make the fixed arrow slightly more substantial without changing normal mode.
if t.count("Icon(Icons.navigation, size: 58, color: Colors.white)") != 1:
    raise SystemExit("100299 outer driver arrow size anchor missing")
t=t.replace("Icon(Icons.navigation, size: 58, color: Colors.white)",
            "Icon(Icons.navigation, size: 64, color: Colors.white)",1)
if t.count("Icon(Icons.navigation, size: 46, color: Color(0xFF087D45))") != 1:
    raise SystemExit("100299 inner driver arrow size anchor missing")
t=t.replace("Icon(Icons.navigation, size: 46, color: Color(0xFF087D45))",
            "Icon(Icons.navigation, size: 50, color: Color(0xFF087D45))",1)

# 4) Thicken only the live green route while Driver View is on.
layer_start=t.find("                        if (routePoints.length >= 2)")
if layer_start<0:
    raise SystemExit("100299 route layer start missing")
layer_end=t.find("                        MarkerLayer(markers: markers),",layer_start)
if layer_end<0:
    raise SystemExit("100299 route layer end missing")
b=t[layer_start:layer_end]
for old,new,label in [
    ("strokeWidth: tripStarted ? 13 : 10,",
     "strokeWidth: _driverViewEnabled ? 17 : (tripStarted ? 13 : 10),",
     "outer route width"),
    ("strokeWidth: tripStarted ? 9 : 7,",
     "strokeWidth: _driverViewEnabled ? 12 : (tripStarted ? 9 : 7),",
     "dark route width"),
]:
    if b.count(old)!=1:
        raise SystemExit(f"100299 {label}: count {b.count(old)}")
    b=b.replace(old,new,1)

# The trip-only bright green center stroke is unique in this route block.
if b.count("strokeWidth: 5,")!=1:
    raise SystemExit(f"100299 bright route width count {b.count('strokeWidth: 5,')}")
b=b.replace("strokeWidth: 5,",
            "strokeWidth: _driverViewEnabled ? 7 : 5,",1)
t=t[:layer_start]+b+t[layer_end:]

p.write_text(t)
print("DEDA 100299 convincing Driver View visual finish applied.")
