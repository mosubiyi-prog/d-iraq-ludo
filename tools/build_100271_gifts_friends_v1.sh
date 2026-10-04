#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct and validate proven DEDA 100270 baseline =='
DEDA_100270_PREFLIGHT_ONLY=1 bash tools/build_100270_social_fixes_admin_gems.sh

echo '== Apply DEDA 100271 gifts/friends layer only =='
python3 tools/gifts_backend_100271_2026_10_05.py
python3 tools/admin_gifts_ui_100271_2026_10_05.py
python3 tools/gifts_main_ui_100271_2026_10_05.py
python3 tools/gift_nav_badge_fix_100271_2026_10_05.py
python3 tools/firestore_gifts_100271_2026_10_05.py

echo '== Format only sources changed by 100271 =='
dart format \
  lib/main.dart \
  lib/deda_backend.dart \
  lib/admin_pages.dart

echo '== Validate all DEDA 100271 requirements =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py

echo '== Revalidate critical existing app invariants =='
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer: all 100271 touched Dart sources =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/deda_backend.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/admin_pages.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo 'DEDA 100271 preflight completed successfully.'

if [[ "${DEDA_100271_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  echo '100271 preflight-only mode: APK intentionally not built.'
  exit 0
fi

echo '== Build exactly one signed APK: DEDA 100271 =='
flutter build apk --release --build-number=100271 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100271 signed APK build completed successfully.'
