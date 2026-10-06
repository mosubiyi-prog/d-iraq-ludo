#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct proven DEDA 100287 baseline =='
DEDA_100272_PREFLIGHT_ONLY=1 bash tools/build_100272_purchase_level_separation.sh

if ! python3 -c 'import PIL' >/dev/null 2>&1; then python3 -m pip install --user pillow; fi
python3 tools/generate_style_art_100273_2026_10_05.py
python3 tools/style_badges_frames_100273_2026_10_05.py
python3 tools/restore_style_marker_100273_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_badges_frames_100273_2026_10_05.py

python3 tools/prepare_style_preview_patch_100274.py
python3 tools/style_preview_100274_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_preview_100274_2026_10_05.py

python3 tools/style_wallet_sync_100275_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_style_wallet_sync_100275_2026_10_05.py

python3 tools/profile_level_task_points_100276_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_profile_level_task_points_100276_2026_10_05.py

python3 tools/profile_level_xp_fix_100277_2026_10_05.py
dart format lib/main.dart
python3 tools/validate_profile_level_xp_fix_100277_2026_10_05.py

python3 tools/level_system_team_admin_polish_100278_2026_10_05.py
dart format lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart
python3 tools/validate_level_system_team_admin_polish_100278_2026_10_05.py

python3 tools/level_team_admin_final_fix_100279_2026_10_05.py
dart format lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart
python3 tools/validate_level_team_admin_final_fix_100279_2026_10_05.py

python3 tools/road_pulse_v2_min_patch_100283.py
dart format lib/main.dart
python3 tools/validate_road_pulse_v2_100283.py

python3 tools/nav_follow_pulse_position_100284.py
dart format lib/main.dart
python3 tools/validate_nav_follow_pulse_position_100284.py

python3 tools/nav_guide_road_pulse_final_ui_100285.py
dart format lib/main.dart
python3 tools/validate_nav_guide_road_pulse_final_ui_100285.py

python3 tools/navigation_road_alignment_reroute_100286.py
dart format lib/main.dart
python3 tools/navigation_live_heading_ui_100286.py
dart format lib/main.dart
python3 tools/validate_navigation_seven_fixes_100286.py

python3 tools/navigation_batch1_100287.py
dart format lib/main.dart
python3 tools/validate_navigation_batch1_100287.py

python3 tools/normalize_navigation_callback_for_batch2_100287.py
python3 tools/navigation_batch2_camera_hazards_100287.py
dart format lib/main.dart
python3 tools/validate_navigation_batch2_100287.py

python3 tools/navigation_batch3_driver_mode_100287.py
dart format lib/main.dart
python3 tools/validate_navigation_batch3_driver_mode_100287.py

echo '== Apply ONLY DEDA 100288 true visual driver perspective =='
python3 tools/driver_perspective_only_100288.py
dart format lib/main.dart
python3 tools/validate_driver_perspective_only_100288.py

echo '== Revalidate unaffected invariants =='
python3 tools/validate_navigation_batch1_100287.py
python3 tools/validate_navigation_batch2_100287.py
python3 tools/validate_navigation_batch3_driver_mode_100287.py
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart

echo 'DEDA 100288 focused perspective preflight passed.'

if [[ "${DEDA_100288_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  echo '100288 preflight-only mode: APK intentionally not built.'
  exit 0
fi

echo '== Build exactly one signed APK: DEDA 100288 driver perspective only =='
flutter build apk --release --build-number=100288 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100288 driver-perspective-only APK build completed successfully.'
