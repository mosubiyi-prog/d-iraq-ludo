from pathlib import Path
import re

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100297 — exactly three scoped navigation polish items:
# 1) keep the visible green route anchored at the route's start until reroute,
# 2) use a slightly closer canonical navigation zoom,
# 3) restore the approved 2026-10-06 navigation color treatment.
# No hazard thresholds, routing provider logic, arrow logic, or reroute logic changes.

def replace_section(src: str, start_token: str, end_token: str, replacement: str, label: str) -> str:
    start = src.find(start_token)
    end = src.find(end_token, start + len(start_token))
    if start < 0 or end < 0:
        raise SystemExit(f"100297: {label} boundary missing")
    return src[:start] + replacement + src[end:]

# ---------------------------------------------------------------------------
# 1) Green route start stays fixed at the route origin.
# _lastRouteOrigin is already refreshed by loadRoute(), so a real reroute
# automatically establishes a new fixed start without touching reroute logic.
# ---------------------------------------------------------------------------
visible_start = text.find("    final visibleRoutePoints = (() {")
visible_end = text.find("    })();", visible_start)
if visible_start < 0 or visible_end < 0:
    raise SystemExit("100297: visible route block missing")
visible_end += len("    })();")
visible = text[visible_start:visible_end]
old_visible_current = "      final current = _displayPosition ?? startPoint;"
new_visible_current = "      final current = _lastRouteOrigin ?? startPoint;"
if visible.count(old_visible_current) != 1:
    raise SystemExit(
        f"100297: expected one moving visible-route origin, found {visible.count(old_visible_current)}"
    )
visible = visible.replace(old_visible_current, new_visible_current, 1)
text = text[:visible_start] + visible + text[visible_end:]

# ---------------------------------------------------------------------------
# 2) Slightly closer canonical navigation zoom.
# 100296 already guarantees start/follow/10-second return share this one value.
# ---------------------------------------------------------------------------
zoom_pattern = re.compile(
    r"final navigationHomeZoom\s*=\s*"
    r"_currentMapZoom\(\)\.clamp\(13\.6, 16\.2\)\.toDouble\(\);"
)
text, zoom_count = zoom_pattern.subn(
    "final navigationHomeZoom = 15.0;",
    text,
    count=1,
)
if zoom_count != 1:
    raise SystemExit(f"100297: navigation home zoom anchor count {zoom_count}")

# ---------------------------------------------------------------------------
# 3) Approved navigation coloring from 2026-10-06.
# Visual blocks only. Keep all live navigation calculations untouched.
# ---------------------------------------------------------------------------
turn_start = text.find("  Widget _buildTurnInstructionBanner(DedaRouteStep step) {")
turn_end = text.find("  int get _currentSpeedKmh {", turn_start)
if turn_start < 0 or turn_end < 0:
    raise SystemExit("100297: turn banner boundaries missing")

turn_block = r'''  Widget _buildTurnInstructionBanner(DedaRouteStep step) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Material(
      color: Colors.transparent,
      elevation: isLandscape ? 2 : 4,
      borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          minHeight: isLandscape ? 38 : 58,
          maxHeight: isLandscape ? 48 : 74,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 6 : 14,
          vertical: isLandscape ? 3 : 11,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [Color(0xFFFFFFFF), Color(0xFFE7F7EE)],
          ),
          borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),
          border: Border.all(
            color: const Color(0xFF7DD7A1).withOpacity(0.72),
            width: 1.2,
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: isLandscape ? 30 : 42,
              height: isLandscape ? 30 : 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDDF5E7),
                borderRadius: BorderRadius.circular(isLandscape ? 8 : 11),
              ),
              child: Icon(
                directionIcon(step),
                size: isLandscape ? 20 : 26,
                color: const Color(0xFF078044),
              ),
            ),
            SizedBox(width: isLandscape ? 5 : 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    step.instruction,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isLandscape ? 11 : 14,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF102A3A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    textDirection: TextDirection.rtl,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          dedaText(
                            'بعد ${formatRouteDistance(_distanceToManeuver(step))}',
                            'In ${formatRouteDistance(_distanceToManeuver(step))}',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isLandscape ? 8.5 : 10.5,
                            color: const Color(0xFF335D4A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (step.lanes.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _buildLaneGuide(step),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:turn_start] + turn_block + text[turn_end:]

speed_start = text.find("  Widget _buildSpeedIndicator() {")
speed_end = text.find("  double _distanceToManeuver(DedaRouteStep step) {", speed_start)
if speed_start < 0 or speed_end < 0:
    raise SystemExit("100297: speed indicator boundaries missing")

speed_block = r'''  Widget _buildSpeedIndicator() {
    return Material(
      color: Colors.transparent,
      elevation: 6,
      shape: const CircleBorder(),
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.30, -0.35),
            colors: [Color(0xFF2E79FF), Color(0xFF0A2D66)],
          ),
          border: Border.all(color: const Color(0xFFBFD8FF), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x550A2D66),
              blurRadius: 9,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_currentSpeedKmh',
              style: const TextStyle(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dedaText('كم/س', 'km/h'),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDDEAFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:speed_start] + speed_block + text[speed_end:]

compact_start = text.find("  Widget _buildCompactNavigationBar() {")
compact_end = text.find("  Widget _buildLandscapePreTripPanel() {", compact_start)
if compact_start < 0 or compact_end < 0:
    raise SystemExit("100297: compact navigation bar boundaries missing")

compact_block = r'''  Widget _buildCompactNavigationBar() {
    final currentRoute = route;
    final remaining = _liveRemainingMeters ?? currentRoute?.distanceMeters;
    final distance = remaining == null ? '—' : formatRouteDistance(remaining);
    var durationSeconds =
        currentRoute == null ? 0.0 : _estimatedDurationSeconds(currentRoute);
    if (currentRoute != null &&
        currentRoute.distanceMeters > 0 &&
        remaining != null) {
      final ratio =
          (remaining / currentRoute.distanceMeters).clamp(0.0, 1.5).toDouble();
      durationSeconds *= ratio;
    }
    final duration = currentRoute == null
        ? '—'
        : formatCompactRouteDuration(durationSeconds);

    Widget roundAction({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
      required Color foreground,
      required Color background,
    }) {
      return Material(
        color: background,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, color: foreground),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      elevation: 9,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [Color(0xFFF8FFFB), Color(0xFFEEF7FF)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCFE8DB), width: 1.1),
        ),
        child: Row(
          textDirection: DedaLanguageState.direction,
          children: [
            roundAction(
              tooltip: dedaText('تشغيل أو كتم الصوت', 'Mute or enable voice'),
              onPressed: _toggleVoice,
              icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
              foreground: const Color(0xFF087D45),
              background: const Color(0xFFDFF6E8),
            ),
            const SizedBox(width: 4),
            roundAction(
              tooltip: dedaText('إبلاغ عن خطر', 'Report hazard'),
              onPressed: _submittingHazard ? null : _showHazardReportSheet,
              icon: Icons.report_problem_outlined,
              foreground: const Color(0xFFE36A00),
              background: const Color(0xFFFFE9CF),
            ),
            const SizedBox(width: 7),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDDF6EE),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                dedaTravelModeIcon(widget.travelMode),
                color: const Color(0xFF087D45),
                size: 24,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: DedaLanguageState.isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    dedaTravelModeLabel(widget.travelMode),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF112B3C),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: DedaLanguageState.isArabic
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Text(
                      '$distance  •  $duration',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF294C5A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            roundAction(
              tooltip: dedaText('إيقاف الرحلة', 'Stop trip'),
              onPressed: () => stopTrip(),
              icon: Icons.stop_rounded,
              foreground: const Color(0xFF0B5D34),
              background: const Color(0xFFCFF1D9),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:compact_start] + compact_block + text[compact_end:]

# Active navigation AppBar coloring only.
appbar_start = text.find("      appBar: tripStarted && _mapFullscreen")
appbar_end = text.find("      body: SafeArea(", appbar_start)
if appbar_start < 0 or appbar_end < 0:
    raise SystemExit("100297: navigation AppBar boundaries missing")
appbar_block = r'''      appBar: tripStarted && _mapFullscreen
          ? null
          : AppBar(
              foregroundColor:
                  tripStarted ? Colors.white : const Color(0xFF18372B),
              backgroundColor: tripStarted ? Colors.transparent : null,
              elevation: tripStarted ? 5 : 0,
              flexibleSpace: tripStarted
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [
                            Color(0xFF007A78),
                            Color(0xFF079E67),
                            Color(0xFF39C979),
                          ],
                        ),
                      ),
                    )
                  : null,
              title: Text(
                tripStarted
                    ? dedaText(
                        'الملاحة • ${dedaTravelModeLabel(widget.travelMode)}',
                        'Navigation • ${dedaTravelModeLabel(widget.travelMode)}',
                      )
                    : dedaText(
                        'الطريق • ${dedaTravelModeLabel(widget.travelMode)}',
                        'Route • ${dedaTravelModeLabel(widget.travelMode)}',
                      ),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: tripStarted ? Colors.white : const Color(0xFF18372B),
                ),
              ),
              centerTitle: true,
            ),
'''
text = text[:appbar_start] + appbar_block + text[appbar_end:]

# Navigation map controls: restore the approved purple/blue/turquoise accents.
map_tooltip = "tooltip: dedaText('نوع الخريطة', 'Map type'),"
map_tooltip_pos = text.find(map_tooltip, appbar_end)
if map_tooltip_pos < 0:
    raise SystemExit("100297: navigation map-style tooltip missing")
map_material = text.rfind("child: Material(", appbar_end, map_tooltip_pos)
map_popup = text.find("child: PopupMenuButton<DedaMapStyle>(", map_material)
if map_material < 0 or map_popup < 0 or map_popup > map_tooltip_pos:
    raise SystemExit("100297: navigation map-style material boundary missing")
map_prefix = text[map_material:map_popup]
map_prefix_new, c = re.subn(
    r"color:\s*Colors\.white\.withOpacity\(0\.94\),",
    "color: tripStarted\n                      ? const Color(0xFFF1E8FF).withOpacity(0.97)\n                      : Colors.white.withOpacity(0.94),",
    map_prefix,
    count=1,
)
if c != 1:
    raise SystemExit("100297: map-style material color anchor missing")
text = text[:map_material] + map_prefix_new + text[map_popup:]

# Re-find tooltip after changing prefix offsets.
map_tooltip_pos = text.find(map_tooltip, appbar_end)
map_child_start = text.find("child: Padding(", map_tooltip_pos)
map_child_end = text.find("                  ),\n                ),", map_child_start)
if map_child_start < 0 or map_child_end < 0:
    raise SystemExit("100297: map-style chip child boundaries missing")
map_child_end += len("                  ),")
map_child = text[map_child_start:map_child_end]
old_icon = "                        const Icon(Icons.layers_outlined),"
if old_icon not in map_child:
    raise SystemExit("100297: map-style icon anchor missing")
map_child = map_child.replace(
    old_icon,
    """                        Icon(
                          Icons.layers_outlined,
                          color: tripStarted
                              ? const Color(0xFF6C2BD9)
                              : const Color(0xFF405047),
                        ),""",
    1,
)
# Replace only the map-style label widget, independent of whether the proven
# baseline formatted its TextStyle as const/non-const or omitted the style.
label_token = "dedaMapStyleLabel(mapStyle)"
label_pos = map_child.find(label_token)
if label_pos < 0:
    raise SystemExit("100297: map-style label text missing")
label_start = map_child.rfind("Text(", 0, label_pos)
if label_start < 0:
    raise SystemExit("100297: map-style Text widget start missing")

depth = 0
label_close = -1
for idx in range(label_start, len(map_child)):
    ch = map_child[idx]
    if ch == "(":
        depth += 1
    elif ch == ")":
        depth -= 1
        if depth == 0:
            label_close = idx + 1
            break
if label_close < 0:
    raise SystemExit("100297: map-style Text widget end missing")
if label_close < len(map_child) and map_child[label_close] == ",":
    label_close += 1

label_new = """Text(
                          dedaMapStyleLabel(mapStyle),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: tripStarted
                                ? const Color(0xFF6C2BD9)
                                : const Color(0xFF405047),
                          ),
                        ),"""
map_child = (
    map_child[:label_start]
    + label_new
    + map_child[label_close:]
)

text = text[:map_child_start] + map_child + text[map_child_end:]

def color_circle_control(src: str, tooltip: str, bg: str, icon_color: str, label: str) -> str:
    pos = src.find(tooltip, appbar_end)
    if pos < 0:
        raise SystemExit(f"100297: {label} tooltip missing")
    material = src.rfind("child: Material(", appbar_end, pos)
    block_end = src.find("                ),", pos)
    if material < 0 or block_end < 0:
        raise SystemExit(f"100297: {label} control boundary missing")
    block_end += len("                ),")
    block = src[material:block_end]
    block, color_count = re.subn(
        r"color:\s*Colors\.white\.withOpacity\(0\.(?:92|94)\),",
        f"color: const Color({bg}).withOpacity(0.97),",
        block,
        count=1,
    )
    if color_count != 1:
        raise SystemExit(f"100297: {label} background color anchor missing")
    icon_match = re.search(r"icon:\s*const Icon\(([^\n\)]*)\),", block)
    if not icon_match:
        raise SystemExit(f"100297: {label} icon anchor missing")
    icon_expr = icon_match.group(1).strip()
    colored = (
        "icon: const Icon(\n"
        f"                      {icon_expr},\n"
        f"                      color: Color({icon_color}),\n"
        "                    ),"
    )
    block = block[:icon_match.start()] + colored + block[icon_match.end():]
    return src[:material] + block + src[block_end:]

text = color_circle_control(
    text,
    "tooltip: dedaText('شرح الخريطة', 'Map guide'),",
    "0xFFE7F1FF",
    "0xFF1769D2",
    "map info",
)
text = color_circle_control(
    text,
    "tooltip: dedaText('عرض المسار كاملًا', 'Show full route'),",
    "0xFFE1F8F4",
    "0xFF009C89",
    "fit route",
)

path.write_text(text)
print("DEDA 100297 three-point navigation polish applied.")
