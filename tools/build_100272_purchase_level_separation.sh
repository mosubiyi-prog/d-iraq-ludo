#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct and validate proven DEDA 100271 baseline =='
DEDA_100271_PREFLIGHT_ONLY=1 bash tools/build_100271_gifts_friends_v1.sh

echo '== Normalize formatted 100271 style-purchase anchors =='
python3 tools/normalize_style_purchase_anchors_100272_2026_10_05.py

echo '== Apply DEDA 100272 purchase/level separation only =='
python3 tools/style_purchase_separation_100272_2026_10_05.py

echo '== Format only the source changed by 100272 =='
dart format lib/main.dart

echo '== Validate DEDA 100272 requirements =='
python3 tools/validate_purchase_level_separation_100272_2026_10_05.py

echo '== Revalidate critical DEDA 100271 gift/friend invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo 'DEDA 100272 preflight completed successfully.'

if [[ "${DEDA_100272_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  echo '100272 preflight-only mode: APK intentionally not built.'
  exit 0
fi

echo '== Build exactly one signed APK: DEDA 100272 =='
flutter build apk --release --build-number=100272 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100272 signed APK build completed successfully.'
