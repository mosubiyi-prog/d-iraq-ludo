#!/usr/bin/env bash
set -euo pipefail

# Reuse the exact proven 100267 reconstruction/validation pipeline, but stop it
# before its APK build. This prevents drift while keeping 100269 to one final APK.
echo '== Preserve 100269 social service =='
cp lib/deda_social_service.dart /tmp/deda_social_service_100269.dart

awk '/== Build signed APK 100267 ==/{exit} {print}' \
  tools/build_100267_add_friend_ui.sh > /tmp/deda_base_100267_no_apk.sh
chmod +x /tmp/deda_base_100267_no_apk.sh

echo '== Reconstruct and validate proven 100267 base (no APK) =='
bash /tmp/deda_base_100267_no_apk.sh

# flutter create must never be allowed to replace the 100269 service source.
cp /tmp/deda_social_service_100269.dart lib/deda_social_service.dart

echo '== Apply consolidated personal social system 100269 =='
python3 tools/social_system_consolidated_100269_2026_10_04.py
python3 tools/fix_social_service_types_100269_2026_10_04.py
python3 tools/stabilize_social_identity_100269_2026_10_04.py
python3 tools/refine_social_runtime_100269_2026_10_04.py
dart format lib/main.dart lib/deda_social_service.dart

echo '== Apply and validate 100269 Firestore rules locally =='
python3 tools/add_social_firestore_rules_100269_2026_10_04.py
python3 tools/stabilize_social_rules_identity_100269_2026_10_04.py
python3 tools/validate_social_system_100269_2026_10_04.py

echo '== Revalidate critical pre-existing DEDA invariants after 100269 =='
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Dart/Flutter error analysis for changed sources =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/deda_social_service.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo 'DEDA 100269 preflight completed successfully.'

if [[ "${DEDA_100269_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  echo 'Preflight-only mode: APK build intentionally skipped.'
  exit 0
fi

echo '== Build one signed APK: DEDA 100269 =='
flutter build apk --release --build-number=100269 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100269 signed APK build completed successfully.'
