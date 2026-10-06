from pathlib import Path

runner_path = Path("tools/run_nav_heading_touch10_smooth_100290.py")
runner = runner_path.read_text()

old = 'follow_end = text.find("  double _distanceToManeuver", focus_start)'
new = 'follow_end = text.find("  void _animateNavigationMarker(", focus_start)'

if runner.count(old) != 1:
    raise SystemExit(
        "100290 safe runner: expected exactly one broad follow/focus boundary"
    )

runner = runner.replace(old, new, 1)

exec(
    compile(runner, str(runner_path), "exec"),
    {"__name__": "__main__"},
)
