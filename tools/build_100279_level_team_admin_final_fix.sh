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

echo '== Revalidate unaffected invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart

echo '== Build exactly one signed APK: DEDA 100279 =='
flutter build apk --release --build-number=100279 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100279 signed APK build completed successfully.'
