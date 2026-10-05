#!/usr/bin/env bash
set -euo pipefail

echo '== DEDA 100273: preserve proven 100272 source and generate deterministic artwork =='

if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 -m pip install --user pillow
fi

# Generate the 6 approved style slots directly during the isolated 100273
# build. No damaged binary reference is required.
python3 tools/generate_style_art_100273_2026_10_05.py
python3 tools/style_badges_frames_100273_2026_10_05.py

echo '== Format only the source changed by 100273 =='
dart format lib/main.dart

echo '== Validate 100273 contract =='
python3 tools/validate_style_badges_frames_100273_2026_10_05.py

echo '== Revalidate critical earlier invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo '== Build exactly one signed APK: DEDA 100273 =='
flutter build apk --release --build-number=100273 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100273 signed APK build completed successfully.'
