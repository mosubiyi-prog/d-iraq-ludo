from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

start_marker = "  Widget _buildHazardWarning(DedaRoadHazard hazard) {"
end_marker = "  Widget _buildLandscapeDrivingStatus() {"

start = text.find(start_marker)
if start < 0:
    raise SystemExit("100283 Road Pulse: hazard warning start marker not found")
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("100283 Road Pulse: landscape status marker not found")

replacement = r'''  Widget _buildHazardWarning(DedaRoadHazard hazard) {
    final distance = _metersBetween(startPoint, hazard.location);
    final confidence = hazard.confirmations >= 2
        ? dedaText(
            '${hazard.confirmations} تأكيد',
            '${hazard.confirmations} confirmations',
          )
        : dedaText('بلاغ جديد', 'New report');

    var accent = const Color(0xFFFFA11A);
    switch (hazard.type) {
      case 'roadworks':
      case 'maintenance':
        accent = const Color(0xFFFFD33D);
        break;
      case 'detour':
        accent = const Color(0xFFFF4B4B);
        break;
      case 'speed_camera':
        accent = const Color(0xFFB67CFF);
        break;
      case 'checkpoint':
        accent = const Color(0xFF55B7FF);
        break;
      case 'accident':
        accent = const Color(0xFFFF5A4F);
        break;
      case 'congestion':
        accent = const Color(0xFFFF7A1A);
        break;
      case 'road_object':
        accent = const Color(0xFFFF9A2F);
        break;
      case 'flooded':
        accent = const Color(0xFF43D7FF);
        break;
      case 'bump':
      default:
        accent = const Color(0xFFFFA11A);
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
        elevation: 5,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54, maxHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [Color(0xFF123046), Color(0xFF071A27)],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: accent.withOpacity(0.90), width: 1.4),
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
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.55)),
                ),
                child: Icon(hazard.icon, color: accent, size: 24),
              ),
              const SizedBox(width: 7),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
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
                        color: accent.withOpacity(0.97),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white70,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

'''

text = text[:start] + replacement + text[end:]
path.write_text(text)
print("DEDA 100283 minimal Road Pulse banner patch applied.")
