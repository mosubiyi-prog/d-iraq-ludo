from pathlib import Path

script_path = Path("tools/nav_heading_touch10_smooth_100290.py")
script = script_path.read_text()
exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
