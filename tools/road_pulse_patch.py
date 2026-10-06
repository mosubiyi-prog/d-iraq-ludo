from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

if "Widget _buildRoadPulse()" in text:
    print("DEDA Road Pulse is already integrated in the build source.")
    raise SystemExit(0)


def replace_section(source: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise SystemExit(f"Road Pulse patch: start marker not found: {start_marker!r}")
    end = source.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"Road Pulse patch: end marker not found: {end_marker!r}")
    return source[:start] + replacement + source[end:]


road_pulse_block = r'''  Color _roadPulseAccentForType(String type) {
    switch (type) {
      case 'bump':
        return const Color(0xFFFFA11A);
      case 'roadworks':
      case 'maintenance':
        return const Color(0xFFFFD33D);
      case 'detour':
        return const Color(0xFFFF3B3B);
      case 'speed_camera':
        return const Color(0xFFB67CFF);
      case 'checkpoint':
        return const Color(0xFF55B7FF);
      case 'accident':
        return const Color(0xFFFF5A4F);
      case 'congestion':
        return const Color(0xFFFF7A1A);
      case 'road_object':
        return const Color(0xFFFF9A2F);
      case 'flooded':
        return const Color(0xFF43D7FF);
      default:
        return const Color(0xFF9CB4FF);
    }
  }

  Color _roadPulseAccent(DedaRoadHazard? hazard) => hazard == null
      ? const Color(0xFF7CFFB2)
      : _roadPulseAccentForType(hazard.type);

  List<Color> _roadPulseGradient(DedaRoadHazard? hazard) {
    switch (hazard?.type) {
      case 'bump':
        return const [Color(0xFF6B3510), Color(0xFF2B1811)];
      case 'roadworks':
      case 'maintenance':
        return const [Color(0xFF6E5900), Color(0xFF2E2700)];
      case 'detour':
        return const [Color(0xFF95141B), Color(0xFF43070B)];
      case 'speed_camera':
        return const [Color(0xFF6330C7), Color(0xFF281050)];
      case 'checkpoint':
        return const [Color(0xFF0D67B5), Color(0xFF06365F)];
      case 'accident':
        return const [Color(0xFFA81919), Color(0xFF4B0707)];
      case 'congestion':
        return const [Color(0xFFC65308), Color(0xFF5A2104)];
      case 'road_object':
        return const [Color(0xFF8B4307), Color(0xFF3D1E03)];
      case 'flooded':
        return const [Color(0xFF0086A9), Color(0xFF003E59)];
      default:
        return const [Color(0xFF087A47), Color(0xFF064C35)];
    }
  }

  String _roadPulseHint(DedaRoadHazard hazard) {
    switch (hazard.type) {
      case 'bump':
        return dedaText('خفف السرعة', 'Slow down');
      case 'roadworks':
      case 'maintenance':
        return dedaText('انتبه لأعمال الطريق', 'Road works ahead');
      case 'detour':
        return dedaText('استعد للتحويلة', 'Prepare for the detour');
      case 'speed_camera':
        return dedaText('التزم بالسرعة', 'Obey the speed limit');
      case 'checkpoint':
        return dedaText('اتبع التعليمات', 'Follow instructions');
      case 'accident':
        return dedaText('توخَّ الحذر', 'Use caution');
      case 'congestion':
        return dedaText('حركة بطيئة أمامك', 'Slow traffic ahead');
      case 'road_object':
        return dedaText('انتبه للعائق', 'Watch for the obstacle');
      case 'flooded':
        return dedaText('انتبه للمياه', 'Watch for water');
      default:
        return dedaText('انتبه للطريق', 'Watch the road');
    }
  }

  Widget _buildRoadPulse() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final hazard = _activeHazard;
    final accent = _roadPulseAccent(hazard);
    final distance = hazard == null
        ? null
        : _metersBetween(startPoint, hazard.location);
    final title = hazard == null
        ? dedaText(
            'نبض الطريق • الطريق أمامك واضح',
            'Road Pulse • Road ahead is clear',
          )
        : dedaText(
            'نبض الطريق • ${hazard.label}',
            'Road Pulse • ${hazard.label}',
          );
    final subtitle = hazard == null
        ? dedaText(
            'لا توجد مخاطر قريبة على مسارك',
            'No nearby hazards on your route',
          )
        : dedaText(
            'بعد ${formatRouteDistance(distance!)} • ${_roadPulseHint(hazard!)}',
            'In ${formatRouteDistance(distance!)} • ${_roadPulseHint(hazard!)}',
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hazard == null ? null : () => _showHazardDetails(hazard!),
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(
            minHeight: isLandscape ? 38 : 48,
            maxHeight: isLandscape ? 48 : 64,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 6 : 8,
            vertical: isLandscape ? 3 : 5,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: _roadPulseGradient(hazard),
            ),
            borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
            border: Border.all(
              color: accent.withOpacity(0.88),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.23),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: isLandscape ? 30 : 38,
                height: isLandscape ? 30 : 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(isLandscape ? 8 : 10),
                  border: Border.all(color: accent.withOpacity(0.55)),
                ),
                child: Icon(
                  hazard?.icon ?? Icons.route_rounded,
                  color: accent,
                  size: isLandscape ? 20 : 24,
                ),
              ),
              SizedBox(width: isLandscape ? 5 : 7),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLandscape ? 10.5 : 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: accent.withOpacity(0.96),
                        fontSize: isLandscape ? 8.2 : 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isLandscape ? 3 : 5),
              Icon(
                hazard == null
                    ? Icons.check_circle_rounded
                    : Icons.chevron_left_rounded,
                color: hazard == null ? accent : Colors.white70,
                size: isLandscape ? 19 : 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

'''

text = replace_section(
    text,
    "  Widget _buildHazardWarning(DedaRoadHazard hazard) {",
    "  Widget _buildLandscapeDrivingStatus() {",
    road_pulse_block,
)

turn_banner_block = r'''  Widget _buildTurnInstructionBanner(DedaRouteStep step) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Material(
      color: Colors.transparent,
      elevation: 4,
      borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          minHeight: isLandscape ? 38 : 48,
          maxHeight: isLandscape ? 48 : 64,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 6 : 8,
          vertical: isLandscape ? 3 : 5,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [Color(0xFFFFFFFF), Color(0xFFE7F7EE)],
          ),
          borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
          border: Border.all(
            color: const Color(0xFF7DD7A1).withOpacity(0.72),
            width: 1.2,
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: isLandscape ? 30 : 38,
              height: isLandscape ? 30 : 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDDF5E7),
                borderRadius: BorderRadius.circular(isLandscape ? 8 : 10),
              ),
              child: Icon(
                directionIcon(step),
                size: isLandscape ? 20 : 24,
                color: const Color(0xFF078044),
              ),
            ),
            SizedBox(width: isLandscape ? 5 : 7),
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
                      fontSize: isLandscape ? 11 : 12.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF102A3A),
                    ),
                  ),
                  const SizedBox(height: 1),
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
                            fontSize: isLandscape ? 8.5 : 9.5,
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

text = replace_section(
    text,
    "  Widget _buildTurnInstructionBanner(DedaRouteStep step) {",
    "  int get _currentSpeedKmh {",
    turn_banner_block,
)

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

text = replace_section(
    text,
    "  Widget _buildSpeedIndicator() {",
    "  double _distanceToManeuver(DedaRouteStep step) {",
    speed_block,
)

compact_nav_block = r'''  Widget _buildCompactNavigationBar() {
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

text = replace_section(
    text,
    "  Widget _buildCompactNavigationBar() {",
    "  Widget _buildLandscapePreTripPanel() {",
    compact_nav_block,
)

anchor = """                child: _buildTurnInstructionBanner(firstUsefulStep!),
              ),
            if (tripStarted && !isLandscape)
"""
replacement = """                child: _buildTurnInstructionBanner(firstUsefulStep!),
              ),
            if (tripStarted)
              Positioned(
                top: isLandscape ? 60 : 82,
                left: isLandscape ? 140 : 68,
                right: isLandscape ? 140 : 118,
                child: _buildRoadPulse(),
              ),
            if (tripStarted && !isLandscape)
"""
if anchor not in text:
    raise SystemExit("Road Pulse patch: turn banner placement anchor not found")
text = text.replace(anchor, replacement, 1)

speed_pos = """            if (tripStarted && !isLandscape)
              Positioned(
                top: 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
"""
speed_new = """            if (tripStarted && !isLandscape)
              Positioned(
                top: 154,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
"""
if speed_pos not in text:
    raise SystemExit("Road Pulse patch: portrait speed placement not found")
text = text.replace(speed_pos, speed_new, 1)

old_hazard_position = """            if (tripStarted && _activeHazard != null)
              Positioned(
                top: isLandscape ? 78 : 188,
                left: isLandscape ? 96 : 18,
                right: isLandscape ? 96 : 18,
                child: _buildHazardWarning(_activeHazard!),
              ),
"""
if old_hazard_position not in text:
    raise SystemExit("Road Pulse patch: old hazard warning placement not found")
text = text.replace(old_hazard_position, "", 1)

appbar_start = text.find("      appBar: tripStarted && _mapFullscreen")
appbar_end = text.find("      body: SafeArea(", appbar_start)
if appbar_start < 0 or appbar_end < 0:
    raise SystemExit("Road Pulse patch: navigation app bar block not found")
appbar = r'''      appBar: tripStarted && _mapFullscreen
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
text = text[:appbar_start] + appbar + text[appbar_end:]

marker_start = text.find("        ..._roadHazards")
marker_end = text.find("      Marker(\n        point: destinationPoint", marker_start)
if marker_start < 0 or marker_end < 0:
    raise SystemExit("Road Pulse patch: hazard marker region not found")
marker_block = text[marker_start:marker_end]
marker_anchor = """          final overlapsLiveArrow =
              _metersBetween(startPoint, hazard.location) <= 25;
          return Marker(
"""
marker_replacement = """          final overlapsLiveArrow =
              _metersBetween(startPoint, hazard.location) <= 25;
          final hazardAccent = _roadPulseAccent(hazard);
          return Marker(
"""
if marker_anchor not in marker_block:
    raise SystemExit("Road Pulse patch: hazard marker accent anchor not found")
marker_block = marker_block.replace(marker_anchor, marker_replacement, 1)
marker_block = marker_block.replace(
    "color: const Color(0xFFFFF4E5).withOpacity(0.97),",
    "color: hazardAccent.withOpacity(0.16),",
    1,
)
marker_block = marker_block.replace(
    "color: const Color(0xFFB65A00),\n                        width: 2,",
    "color: hazardAccent,\n                        width: 2,",
    1,
)
marker_block = marker_block.replace(
    "color: const Color(0xFFB65A00),\n                    ),",
    "color: hazardAccent,\n                    ),",
    1,
)
text = text[:marker_start] + marker_block + text[marker_end:]

report_icon = """                          leading: Icon(
                            DedaRoadHazard.iconForType(type),
                            color: const Color(0xFFB65A00),
                          ),
"""
report_icon_new = """                          leading: Icon(
                            DedaRoadHazard.iconForType(type),
                            color: _roadPulseAccentForType(type),
                          ),
"""
if report_icon not in text:
    raise SystemExit("Road Pulse patch: hazard report icon block not found")
text = text.replace(report_icon, report_icon_new, 1)

map_style_anchor = """                child: Material(
                  color: Colors.white.withOpacity(0.94),
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: PopupMenuButton<DedaMapStyle>(
"""
map_style_new = """                child: Material(
                  color: tripStarted
                      ? const Color(0xFFF1E8FF).withOpacity(0.97)
                      : Colors.white.withOpacity(0.94),
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: PopupMenuButton<DedaMapStyle>(
"""
if map_style_anchor not in text:
    raise SystemExit("Road Pulse patch: map style material anchor not found")
text = text.replace(map_style_anchor, map_style_new, 1)

map_chip = """                          const Icon(Icons.layers_outlined),
                          const SizedBox(width: 6),
                          Text(dedaMapStyleLabel(mapStyle)),
"""
map_chip_new = """                          Icon(
                            Icons.layers_outlined,
                            color: tripStarted
                                ? const Color(0xFF6C2BD9)
                                : const Color(0xFF405047),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dedaMapStyleLabel(mapStyle),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: tripStarted
                                  ? const Color(0xFF6C2BD9)
                                  : const Color(0xFF405047),
                            ),
                          ),
"""
if map_chip not in text:
    raise SystemExit("Road Pulse patch: map style chip content not found")
text = text.replace(map_chip, map_chip_new, 1)

info_block = """                child: Material(
                  color: Colors.white.withOpacity(0.94),
                  elevation: 2,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: dedaText('شرح الخريطة', 'Map guide'),
                    onPressed: showMapLegend,
                    icon: const Icon(Icons.info_outline),
                  ),
                ),
"""
info_new = """                child: Material(
                  color: const Color(0xFFE7F1FF).withOpacity(0.97),
                  elevation: 3,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: dedaText('شرح الخريطة', 'Map guide'),
                    onPressed: showMapLegend,
                    icon: const Icon(
                      Icons.info_outline,
                      color: Color(0xFF1769D2),
                    ),
                  ),
                ),
"""
if info_block not in text:
    raise SystemExit("Road Pulse patch: map info control not found")
text = text.replace(info_block, info_new, 1)

fit_block = """                child: Material(
                  color: Colors.white.withOpacity(0.94),
                  elevation: 2,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: dedaText('عرض المسار كاملًا', 'Show full route'),
                    onPressed: () => _fitRouteOnMap(navigation: tripStarted),
                    icon: const Icon(Icons.fit_screen),
                  ),
                ),
"""
fit_new = """                child: Material(
                  color: const Color(0xFFE1F8F4).withOpacity(0.97),
                  elevation: 3,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: dedaText('عرض المسار كاملًا', 'Show full route'),
                    onPressed: () => _fitRouteOnMap(navigation: tripStarted),
                    icon: const Icon(
                      Icons.fit_screen,
                      color: Color(0xFF009C89),
                    ),
                  ),
                ),
"""
if fit_block not in text:
    raise SystemExit("Road Pulse patch: fit route control not found")
text = text.replace(fit_block, fit_new, 1)

checks = [
    "Widget _buildRoadPulse()",
    "case 'speed_camera':",
    "child: _buildRoadPulse()",
    "final hazardAccent = _roadPulseAccent(hazard);",
    "'نبض الطريق • الطريق أمامك واضح'",
    "top: isLandscape ? 60 : 82,",
    "left: isLandscape ? 140 : 68,",
    "right: isLandscape ? 140 : 118,",
]
for item in checks:
    if item not in text:
        raise SystemExit(f"Road Pulse patch: missing safety check: {item}")
if "_buildHazardWarning(" in text:
    raise SystemExit("Road Pulse patch: legacy hazard banner still remains")

path.write_text(text)
print("DEDA Road Pulse navigation patch applied and verified.")
