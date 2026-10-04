#!/usr/bin/env bash
set -euo pipefail

# Reuse the exact successful 100267 preparation/validation chain, but skip its
# final APK build. 100268 then applies only the compact social-field polish.
sed '/flutter build apk --release --build-number=100267 --dart-define=USE_NEXT_GEN_SDK=true/d' \
  tools/build_100267_add_friend_ui.sh > /tmp/build_100267_without_apk.sh
chmod +x /tmp/build_100267_without_apk.sh
bash /tmp/build_100267_without_apk.sh

echo '== Apply 100268 compact social fields =='
python3 tools/compact_social_fields_100268_2026_10_04.py
dart format lib/main.dart

echo '== Validate 100268 compact social fields =='
python3 tools/validate_compact_social_fields_100268_2026_10_04.py
python3 tools/validate_add_friend_ui_100267_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Build signed APK 100268 =='
flutter build apk --release --build-number=100268 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100268 compact social fields build completed successfully.'
