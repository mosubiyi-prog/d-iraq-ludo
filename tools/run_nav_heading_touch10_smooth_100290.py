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

# Safety correction only: the original focused patch grouped _followLivePosition
# and _focusNavigationPosition up to a later method. In the reconstructed 100286
# source, unrelated navigation/hazard/UI methods can live between those methods.
# Target each function by its own balanced braces and preserve everything between.
follow_marker = "# ---- camera helpers: inserted immediately before live follow ----"
helpers_marker = "helpers = '''  double _cameraEaseInOut(double t) {"
follow_section_start = script.find(follow_marker)
helpers_start = script.find(helpers_marker, follow_section_start)
if follow_section_start < 0 or helpers_start < 0:
    raise SystemExit("100290 runner: follow safety section markers missing")

safe_follow_prefix = r'''# ---- camera helpers: inserted immediately before live follow ----
def _find_100290_function_close(source, start, label):
    open_brace = source.find("{", start, start + 180)
    if open_brace < 0:
        raise SystemExit(f"100290: {label} opening brace missing")
    depth = 0
    for i in range(open_brace, min(len(source), start + 5000)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    raise SystemExit(f"100290: {label} closing brace missing")

follow_start = text.find("  void _followLivePosition(LatLng current) {")
if follow_start < 0:
    raise SystemExit("100290: live-follow function missing")
follow_close = _find_100290_function_close(text, follow_start, "live-follow")
old_follow_block = text[follow_start:follow_close + 1]
required_follow_tokens = (
    "final lookAhead =",
    "_pointAlongBearing(current, heading, lookAhead)",
    "_mapController.moveAndRotate",
)
if any(token not in old_follow_block for token in required_follow_tokens):
    raise SystemExit("100290: live-follow function is not expected 100286 implementation")

focus_start = text.find("  void _focusNavigationPosition() {", follow_close + 1)
if focus_start < 0:
    raise SystemExit("100290: navigation-focus function missing")
focus_close = _find_100290_function_close(text, focus_start, "navigation-focus")
old_focus_block = text[focus_start:focus_close + 1]
required_focus_tokens = (
    "final navigationZoom =",
    "final lookAhead =",
    "_mapController.moveAndRotate",
)
if any(token not in old_focus_block for token in required_focus_tokens):
    raise SystemExit("100290: navigation-focus function is not expected 100286 implementation")

'''
script = script[:follow_section_start] + safe_follow_prefix + script[helpers_start:]

old_follow_write = "text = text[:follow_start] + helpers + new_follow_block + text[follow_end:]"
new_follow_write = '''new_focus_signature = "  void _focusNavigationPosition() {"
new_focus_offset = new_follow_block.find(new_focus_signature)
if new_focus_offset <= 0:
    raise SystemExit("100290: new follow/focus split missing")
new_follow_only = new_follow_block[:new_focus_offset]
new_focus_only = new_follow_block[new_focus_offset:]

# Replace only live-follow, inserting helpers immediately before it.
text = text[:follow_start] + helpers + new_follow_only + text[follow_close + 1:]

# Re-find focus after the first replacement and replace only that function.
focus_start = text.find(new_focus_signature, follow_start + len(helpers) + len(new_follow_only))
if focus_start < 0:
    raise SystemExit("100290: navigation-focus function missing after live-follow replacement")
focus_close = _find_100290_function_close(text, focus_start, "navigation-focus")
text = text[:focus_start] + new_focus_only + text[focus_close + 1:]'''
if script.count(old_follow_write) != 1:
    raise SystemExit("100290 runner: expected exactly one grouped follow/focus replacement")
script = script.replace(old_follow_write, new_follow_write, 1)

exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
