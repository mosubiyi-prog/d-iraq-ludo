from pathlib import Path

script_path = Path("tools/nav_heading_touch10_smooth_100290.py")
script = script_path.read_text()

# Safety correction only: keep the _resolvedHeading replacement inside that
# function's own braces. This prevents any neighboring hazard/navigation/UI
# methods from being removed. No intended 100290 behavior is changed here.
old_boundary = '''resolver_start = text.find("  double _resolvedHeading(Position position, LatLng current) {")
resolver_end = text.find(
    "  ({LatLng point, double distance, double fraction}) _projectToSegment(",
    resolver_start,
)
if resolver_start < 0 or resolver_end < 0:
    raise SystemExit("100290: heading resolver boundary missing")
old_resolver = text[resolver_start:resolver_end]
'''
new_boundary = '''resolver_start = text.find("  double _resolvedHeading(Position position, LatLng current) {")
if resolver_start < 0:
    raise SystemExit("100290: heading resolver start missing")
resolver_open = text.find("{", resolver_start, resolver_start + 160)
if resolver_open < 0:
    raise SystemExit("100290: heading resolver opening brace missing")
resolver_depth = 0
resolver_close = -1
for i in range(resolver_open, min(len(text), resolver_start + 3000)):
    ch = text[i]
    if ch == "{":
        resolver_depth += 1
    elif ch == "}":
        resolver_depth -= 1
        if resolver_depth == 0:
            resolver_close = i
            break
if resolver_close < 0:
    raise SystemExit("100290: heading resolver closing brace missing")
old_resolver = text[resolver_start:resolver_close + 1]
'''
if script.count(old_boundary) != 1:
    raise SystemExit("100290 runner: expected exactly one old heading boundary")
script = script.replace(old_boundary, new_boundary, 1)

old_write = "text = text[:resolver_start] + new_resolver + text[resolver_end:]"
new_write = "text = text[:resolver_start] + new_resolver + text[resolver_close + 1:]"
if script.count(old_write) != 1:
    raise SystemExit("100290 runner: expected exactly one old heading replacement")
script = script.replace(old_write, new_write, 1)

exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
