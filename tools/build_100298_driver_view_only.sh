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

echo '== Revalidate unaffected invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart

echo '== Build exactly one signed APK: DEDA 100298 Driver View only =='
flutter build apk --release --build-number=100298 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100298 Driver View only APK build completed successfully.'
