from pathlib import Path

patch_path = Path("tools/nav_heading_touch10_smooth_100290.py")
patch = patch_path.read_text()

old = 'follow_end = text.find("  double _distanceToManeuver", focus_start)'
new = 'follow_end = text.find("  void _animateNavigationMarker(", focus_start)'

if patch.count(old) != 1:
    raise SystemExit(
        "100290 safe runner: expected exactly one broad follow/focus boundary"
    )

patch = patch.replace(old, new, 1)

exec(
    compile(patch, str(patch_path), "exec"),
    {"__name__": "__main__"},
)
