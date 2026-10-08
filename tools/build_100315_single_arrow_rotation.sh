#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct and validate proven DEDA 100272 baseline =='
DEDA_100272_PREFLIGHT_ONLY=1 bash tools/build_100272_purchase_level_separation.sh

echo '== Reconstruct DEDA 100273 badge/frame layer =='
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 -m pip install --user pillow
fi
python3 tools/generate_style_art_100273_2026_10_05.py
python3 tools/style_badges_frames_100273_2026_10_05.py
python3 tools/restore_style_marker_100273_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_badges_frames_100273_2026_10_05.py

echo '== Reconstruct proven DEDA 100274 sticky preview =='
python3 tools/prepare_style_preview_patch_100274.py
python3 tools/style_preview_100274_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_preview_100274_2026_10_05.py

echo '== Reconstruct proven DEDA 100275 wallet synchronization =='
python3 tools/style_wallet_sync_100275_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_wallet_sync_100275_2026_10_05.py

echo '== Reconstruct DEDA 100276 profile level UI + full balance =='
python3 tools/profile_level_task_points_100276_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_profile_level_task_points_100276_2026_10_05.py

echo '== Reconstruct proven DEDA 100277 dedicated level XP separation =='
python3 tools/profile_level_xp_fix_100277_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_profile_level_xp_fix_100277_2026_10_05.py

echo '== Reconstruct DEDA 100278 progressive levels + team names + admin polish =='
python3 tools/level_system_team_admin_polish_100278_2026_10_05.py
dart format lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart
python3 tools/validate_level_system_team_admin_polish_100278_2026_10_05.py

echo '== Apply final DEDA 100279 corrections =='
python3 tools/level_team_admin_final_fix_100279_2026_10_05.py
dart format lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart
python3 tools/validate_level_team_admin_final_fix_100279_2026_10_05.py

echo '== Reapply tested DEDA 100283 Road Pulse v2 =='
python3 tools/road_pulse_v2_min_patch_100283.py
dart format lib/main.dart
python3 tools/validate_road_pulse_v2_100283.py

echo '== Reapply tested DEDA 100284 live-follow fix =='
python3 tools/nav_follow_pulse_position_100284.py
dart format lib/main.dart
python3 tools/validate_nav_follow_pulse_position_100284.py

echo '== Reapply tested DEDA 100285 navigation UI =='
python3 tools/nav_guide_road_pulse_final_ui_100285.py
dart format lib/main.dart
python3 tools/validate_nav_guide_road_pulse_final_ui_100285.py

echo '== Apply DEDA 100286 road alignment + reroute fixes =='
python3 tools/navigation_road_alignment_reroute_100286.py
dart format lib/main.dart

echo '== Apply DEDA 100286 live guidance + heading-up + adaptive UI =='
python3 tools/navigation_live_heading_ui_100286.py
dart format lib/main.dart
python3 tools/validate_navigation_seven_fixes_100286.py

echo '== Apply ONLY DEDA 100293 destination-side green route display =='
python3 tools/green_route_destination_side_100293.py
dart format lib/main.dart
python3 tools/validate_green_route_destination_side_100293.py

echo '== Apply DEDA 100297 three-point navigation polish =='
python3 tools/navigation_core_cleanup_100295.py
dart format lib/main.dart
python3 tools/validate_navigation_core_cleanup_100295.py

echo '== Apply DEDA 100296 route/camera and phone-arrow separation =='
python3 tools/navigation_heading_separation_100296.py
dart format lib/main.dart
python3 tools/validate_navigation_heading_separation_100296.py

echo '== Apply ONLY DEDA 100297 three-point navigation polish =='
python3 tools/navigation_polish_100297.py
dart format lib/main.dart
python3 tools/validate_navigation_polish_100297.py

echo '== Apply ONLY DEDA 100298 Driver View =='
python3 tools/driver_view_only_100298.py
dart format lib/main.dart
python3 tools/validate_driver_view_only_100298.py

echo '== Apply DEDA 100299 Driver View visual finish =='
python3 tools/driver_view_visual_finish_100299.py
dart format lib/main.dart
python3 tools/validate_driver_view_visual_finish_100299.py

echo '== Apply ONLY DEDA 100300 field follow/heading correction =='
python3 tools/driver_follow_heading_100300.py
dart format lib/main.dart
python3 tools/validate_driver_follow_heading_100300.py

echo '== Apply ONLY DEDA 100301 visual navigation corrections =='
python3 tools/driver_visual_core_100301.py
dart format lib/main.dart
python3 tools/validate_driver_visual_core_100301.py

echo '== Apply ONLY DEDA 100302 neighborhood bump warning correction =='
python3 tools/bump_neighborhood_warning_100302.py
dart format lib/main.dart
python3 tools/validate_bump_neighborhood_warning_100302.py

echo '== Apply ONLY DEDA 100303 Driver View anchor/road-up correction =='
python3 tools/driver_anchor_roadup_100303.py
dart format lib/main.dart
python3 tools/validate_driver_anchor_roadup_100303.py

echo '== Apply the three isolated DEDA 100310 Driver View-only changes =='
python3 tools/driver_clean_100310.py
dart format lib/main.dart
echo '== Check the new changes after Dart formatter =='
python3 - <<'PY'
from pathlib import Path
t=Path('lib/main.dart').read_text()
assert 'const Color(0xFFDDF3FF)' not in t, 'artificial sky remained'
assert 'alignment: Alignment(0, isLandscape ? 0.24 : 0.40)' in t, 'arrow anchor changed'
assert '(metersPerPixel * desiredPixels)' in t, 'route camera lead changed'
assert 'setEntry(3, 2, -0.00065 * amount)' in t, 'perspective changed'
assert '_buildFixedDriverArrow(navigationArrowAngle)' in t, 'real heading lost'
print('DEDA 100310 post-format verification passed')
PY

echo '== Apply ONLY DEDA 100311: driver geographic arrow and full map =='
python3 tools/driver_map_anchor_no_sky_100311.py
dart format lib/main.dart
python3 - <<'PY'
from pathlib import Path
x=Path('lib/main.dart').read_text()
assert x.count('_buildFixedDriverArrow(navigationArrowAngle)') == 1, 'duplicate driver arrows'
assert 'point: _displayPosition ?? startPoint' in x, 'GPS marker lost'
assert 'const ColoredBox(color: Color(0xFFF5FAF5))' not in x, 'blank sky background returned'
assert 'scale(1.0 + 0.25 * amount, 1.0 + 0.35 * amount, 1.0)' in x, 'overscan lost'
assert 'angle: navigationArrowAngle' in x, 'normal compass arrow lost'
assert 'Timer(const Duration(seconds: 10)' in x, 'free-touch return changed'
assert 'transformHitTests: true' in x, 'map touch projection lost'
print('DEDA 100311 safety checks after formatter passed')
PY

echo '== Apply DEDA 100312: approved road-hazard safety ONLY =='
python3 tools/hazard_direction_roadclass_100312.py
dart format lib/main.dart lib/deda_road_class_lookup.dart
python3 - <<'PY'
from pathlib import Path
s=Path('lib/main.dart').read_text()
r=Path('lib/deda_road_class_lookup.dart').read_text()
assert "return 500.0;" in s and "return 300.0;" in s, 'external-road warning distances'
assert "return 50.0;" in s and "_hazardRoadClasses[hazard.id] == 'residential'" in s, 'residential warning distances'
assert "_hazardForwardDistance(startPoint, _activeHazard!)" in s, 'marker not route-ahead filtered'
assert "reportedHeading" in s and "_passedHazardIds" in s, 'missing directional/passed report logic'
assert "out geom;" in r and "way(around:45" in r, 'real OSM highway lookup absent'
assert "_offRouteFixes >= 3" in s and "const Duration(seconds: 7)" in s, 'reroute changed'
assert "Timer(const Duration(seconds: 10)" in s, 'free touch changed'
assert "_buildFixedDriverArrow(navigationArrowAngle)" in s, 'driver arrow lost'
print('DEDA 100312 post-Dart-format acceptance and unchanged rerouting checks passed')
PY

echo '== DEDA 100313: restore immediate phone-arrow and accepted live motion only =='
python3 tools/driver_live_arrow_motion_100313.py
dart format lib/main.dart
python3 - <<'PY'
from pathlib import Path
x=Path('lib/main.dart').read_text()
assert 'change >= 0.6' in x, 'live compass threshold missing'
assert 'if (!_compassHeadingIsFresh && filtered.moving)' in x, 'GPS still overrides phone'
assert 'confirmedDrivingMotion ? 4.0 : unlockDistance' in x, 'fast movement distance missing'
assert 'confirmedDrivingMotion ? 1 : requiredCandidates' in x, 'fast movement release missing'
assert 'position.speedAccuracy <= 2.5' in x, 'speed reliability missing'
assert 'return 500.0;' in x and 'return 300.0;' in x, 'approved hazard distances touched'
assert 'Timer(const Duration(seconds: 10)' in x, 'touch return lost'
assert '_offRouteFixes >= 3' in x, 'reroute changed'
assert '_buildFixedDriverArrow(navigationArrowAngle)' in x, 'real driver arrow changed'
print('DEDA 100313 post-format checks passed')
PY

echo '== DEDA 100314: Road Pulse same size in portrait and landscape ONLY =='
python3 tools/road_pulse_equal_size_100314.py
dart format lib/main.dart
python3 - <<'PY'
from pathlib import Path
import re
s=Path('lib/main.dart').read_text()
start=s.index('  Widget _buildHazardWarning(DedaRoadHazard hazard) {')
end=s.index('  Widget _buildLandscapeDrivingStatus() {', start)
card=s[start:end]
assert 'isLandscape' not in card, 'Road Pulse must have same visual size in both orientations'
assert 'minHeight: 66' in card and 'maxHeight: 82' in card, 'portrait-sized height missing'
assert 'fontSize: 13.5' in card and 'fontSize: 10.2' in card, 'approved typography lost'
start=s.index('            if (tripStarted && _activeHazard != null)\n              Positioned(')
end=s.index('            if (tripStarted && !_autoFollowMap)', start)
overlay=s[start:end]
for token in ['top: isLandscape ? 78 : 92','left: isLandscape ? 136 : 68',
              'right: isLandscape ? null : 118','MediaQuery.sizeOf(context).shortestSide - 186.0',
              '.clamp(140.0, 240.0)']:
    assert token in overlay, 'Road Pulse geometry broken: '+token
assert s.count('_buildHazardWarning(_activeHazard!)') == 1, 'Road Pulse duplicate'
assert '_buildFixedDriverArrow(navigationArrowAngle)' in s and 'change >= 0.6' in s, '100313 instant phone arrow lost'
assert 'confirmedDrivingMotion ? 1 : requiredCandidates' in s, '100313 movement unlock lost'
assert 'Timer(const Duration(seconds: 10)' in s, 'free touch changed'
assert '_offRouteFixes >= 3' in s, 'rerouting changed'
assert 'return 500.0;' in s and 'return 300.0;' in s, 'hazard warnings changed'
print('DEDA 100314 post-format ROAD PULSE and unchanged 100313/100312 navigation acceptance passed')
PY

echo '== DEDA 100315 — compensate FlutterMap camera rotation on the live GPS arrow ONLY =='
python3 tools/arrow_counterrotation_100315.py
dart format lib/main.dart
python3 - <<'PY'
from pathlib import Path
s=Path('lib/main.dart').read_text()
start=s.index('// Keep one small green heading arrow for the user')
end=s.index('    ];', start)
marker=s[start:end]
assert marker.count('rotate: true') == 1, 'live arrow must counter-rotate with map exactly once'
assert marker.count('point: _displayPosition ?? startPoint') == 1, 'user arrow not GPS-anchored'
assert marker.count('_buildFixedDriverArrow(navigationArrowAngle)') == 1, 'Driver View single angle lost'
assert marker.count('angle: navigationArrowAngle') == 1, 'normal arrow angle lost'
assert '((_arrowHeading - _routeCameraHeading + 360) % 360)' in s, 'camera-relative heading lost'
assert 'left: isLandscape ? 136 : 68' in s, 'compact landscape Road Pulse changed'
assert 'right: isLandscape ? null : 118' in s, 'portrait Road Pulse changed'
assert 'change >= 0.6' in s, 'live compass trigger lost'
assert 'confirmedDrivingMotion ? 1 : requiredCandidates' in s, 'live movement lost'
assert 'Timer(const Duration(seconds: 10)' in s, 'free touch lost'
assert '_offRouteFixes >= 3' in s and 'const Duration(seconds: 7)' in s, 'safe reroute lost'
assert 'return 500.0;' in s and 'return 300.0;' in s, 'hazard warning distances changed'
print('DEDA 100315 post-format source safety assertions passed')
PY

echo '== Revalidate unaffected invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/deda_road_class_lookup.dart lib/deda_team_page.dart lib/admin_pages.dart

echo '== Build exactly one signed APK: DEDA 100315 corrected arrow rotation based on 100314 =='
flutter build apk --release --build-number=100315 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100315 single arrow rotation APK build completed successfully.'
