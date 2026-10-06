from pathlib import Path

script_path = Path("tools/nav_heading_touch10_smooth_100290.py")
script = script_path.read_text()

old = "resolver_end = text.find('''  void _animateNavigationMarker(''', resolver_start)"
new = "resolver_end = text.find('''  ({LatLng point, double distance, double fraction}) _projectToSegment(''', resolver_start)"

if script.count(old) != 1:
    raise SystemExit("100290 runner: expected exactly one old resolver-end token")

script = script.replace(old, new, 1)
exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
