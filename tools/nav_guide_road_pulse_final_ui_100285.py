from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# 1) Keep the proven turn-guide logic, but apply the agreed portrait geometry.
turn_start = text.find("  Widget _buildTurnInstructionBanner(DedaRouteStep step) {")
turn_end = text.find("  Widget _buildSpeedIndicator() {", turn_start)
if turn_start < 0 or turn_end < 0:
    raise SystemExit("100285: turn instruction banner block not found")
turn = text[turn_start:turn_end]

replacements = [
    ("color: Colors.white.withOpacity(0.92),", "color: Colors.white.withOpacity(0.96),"),
    ("elevation: 2,", "elevation: isLandscape ? 2 : 4,"),
    ("borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),", "borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),"),
    ("minHeight: isLandscape ? 38 : 48,", "minHeight: isLandscape ? 38 : 58,"),
    ("maxHeight: isLandscape ? 48 : 64,", "maxHeight: isLandscape ? 48 : 74,"),
    ("horizontal: isLandscape ? 6 : 8,", "horizontal: isLandscape ? 6 : 14,"),
    ("vertical: isLandscape ? 3 : 5,", "vertical: isLandscape ? 3 : 11,"),
]
for old, new in replacements:
    if old not in turn:
        raise SystemExit(f"100285: missing turn-banner anchor: {old}")
    turn = turn.replace(old, new, 1)
text = text[:turn_start] + turn + text[turn_end:]

# 2) Replace ONLY the visual Road Pulse card. Detection, distance, voting,
# hazard selection and navigation logic remain untouched.
pulse_start = text.find("  Widget _buildHazardWarning(DedaRoadHazard hazard) {")
pulse_end = text.find("  Widget _buildLandscapeDrivingStatus() {", pulse_start)
if pulse_start < 0 or pulse_end < 0:
    raise SystemExit("100285: Road Pulse block not found")

pulse = r'''  Widget _buildHazardWarning(DedaRoadHazard hazard) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final distance = _metersBetween(startPoint, hazard.location);
    final confidence = hazard.confirmations >= 2
        ? dedaText(
            '${hazard.confirmations} تأكيد',
            '${hazard.confirmations} confirmations',
          )
        : dedaText('بلاغ جديد', 'New report');

    var accent = const Color(0xFFFF9F1C);
    var pulseColors = const <Color>[Color(0xFF5B2708), Color(0xFF271004)];
    switch (hazard.type) {
      case 'roadworks':
      case 'maintenance':
        accent = const Color(0xFFFFD33D);
        pulseColors = const <Color>[Color(0xFF5A4308), Color(0xFF241B03)];
        break;
      case 'detour':
        accent = const Color(0xFFFF5A4F);
        pulseColors = const <Color>[Color(0xFF641515), Color(0xFF280707)];
        break;
      case 'speed_camera':
        accent = const Color(0xFFC784FF);
        pulseColors = const <Color>[Color(0xFF47186B), Color(0xFF1B0928)];
        break;
      case 'checkpoint':
        accent = const Color(0xFFFFA11A);
        pulseColors = const <Color>[Color(0xFF56300A), Color(0xFF211105)];
        break;
      case 'accident':
        accent = const Color(0xFFFF4B4B);
        pulseColors = const <Color>[Color(0xFF6B1111), Color(0xFF280606)];
        break;
      case 'congestion':
        accent = const Color(0xFFFF7A1A);
        pulseColors = const <Color>[Color(0xFF5A2608), Color(0xFF211006)];
        break;
      case 'road_object':
        accent = const Color(0xFFFF9A2F);
        pulseColors = const <Color>[Color(0xFF4D2207), Color(0xFF1E0D03)];
        break;
      case 'flooded':
        accent = const Color(0xFF55B7FF);
        pulseColors = const <Color>[Color(0xFF173B59), Color(0xFF081A29)];
        break;
      case 'bump':
      default:
        accent = const Color(0xFFFF9F1C);
        pulseColors = const <Color>[Color(0xFF5B2708), Color(0xFF271004)];
        break;
    }

    String hint;
    switch (hazard.type) {
      case 'bump':
        hint = dedaText('خفف السرعة', 'Slow down');
        break;
      case 'roadworks':
      case 'maintenance':
        hint = dedaText('انتبه لأعمال الطريق', 'Road works ahead');
        break;
      case 'detour':
        hint = dedaText('استعد للتحويلة', 'Prepare for the detour');
        break;
      case 'speed_camera':
        hint = dedaText('التزم بالسرعة', 'Obey the speed limit');
        break;
      case 'checkpoint':
        hint = dedaText('اتبع التعليمات', 'Follow instructions');
        break;
      case 'accident':
        hint = dedaText('توخَّ الحذر', 'Use caution');
        break;
      case 'congestion':
        hint = dedaText('حركة بطيئة أمامك', 'Slow traffic ahead');
        break;
      case 'road_object':
        hint = dedaText('انتبه للعائق', 'Watch for the obstacle');
        break;
      case 'flooded':
        hint = dedaText('انتبه للمياه', 'Watch for water');
        break;
      default:
        hint = dedaText('انتبه للطريق', 'Watch the road');
        break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showHazardDetails(hazard),
      child: Material(
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
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: pulseColors,
            ),
            borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),
            border: Border.all(color: accent.withOpacity(0.92), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.20),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            textDirection: DedaLanguageState.direction,
            children: [
              Container(
                width: isLandscape ? 34 : 42,
                height: isLandscape ? 34 : 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.17),
                  borderRadius: BorderRadius.circular(isLandscape ? 9 : 12),
                  border: Border.all(color: accent.withOpacity(0.68)),
                ),
                child: Icon(hazard.icon, color: accent, size: isLandscape ? 21 : 26),
              ),
              SizedBox(width: isLandscape ? 6 : 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: DedaLanguageState.isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      dedaText(
                        'نبض الطريق • ${hazard.label}',
                        'Road Pulse • ${hazard.label}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLandscape ? 12 : 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dedaText(
                        'بعد ${formatRouteDistance(distance)} • $hint • $confidence',
                        'In ${formatRouteDistance(distance)} • $hint • $confidence',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      style: TextStyle(
                        color: accent.withOpacity(0.98),
                        fontSize: isLandscape ? 9.5 : 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isLandscape ? 3 : 5),
              Icon(
                DedaLanguageState.isArabic
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: Colors.white70,
                size: isLandscape ? 20 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
text = text[:pulse_start] + pulse + text[pulse_end:]

# 3) Match the Road Pulse overlay to the turn guide width and place it directly
# beneath the guide. Keep the 100284 live-follow behavior unchanged.
old_speed = '''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 182 : 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
new_speed = '''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 174 : 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
if old_speed not in text:
    raise SystemExit("100285: 100284 speed position anchor not found")
text = text.replace(old_speed, new_speed, 1)

old_pulse_position = '''            if (tripStarted && _activeHazard != null)
              Positioned(
                // Keep Road Pulse directly below the turn instruction instead
                // of across the middle of the driving map. In portrait the
                // speed badge moves below it only while an alert is visible.
                top: isLandscape ? 78 : 108,
                left: isLandscape ? 96 : 18,
                right: isLandscape ? 96 : 18,
                child: _buildHazardWarning(_activeHazard!),
              ),
'''
new_pulse_position = '''            if (tripStarted && _activeHazard != null)
              Positioned(
                // Final agreed geometry: Road Pulse sits immediately below the
                // navigation guide and follows the same portrait left/right
                // alignment instead of spanning the center of the map.
                top: isLandscape ? 78 : 92,
                left: isLandscape ? 96 : 68,
                right: isLandscape ? 96 : 118,
                child: _buildHazardWarning(_activeHazard!),
              ),
'''
if old_pulse_position not in text:
    raise SystemExit("100285: 100284 Road Pulse position anchor not found")
text = text.replace(old_pulse_position, new_pulse_position, 1)

# Verify the proven 100284 live-follow protection still exists untouched.
if "onPositionChanged: (_, __) {" not in text:
    raise SystemExit("100285: 100284 live-follow protection missing")
if "the next GPS/animation frame recenters the vehicle" not in text:
    raise SystemExit("100285: live-follow explanatory anchor missing")

path.write_text(text)
print("DEDA 100285 navigation guide + Road Pulse final UI patch applied.")
