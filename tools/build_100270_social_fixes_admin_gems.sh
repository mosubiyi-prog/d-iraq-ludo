#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct proven DEDA 100269 base without APK =='
DEDA_100269_PREFLIGHT_ONLY=1 bash tools/build_100269_social_system.sh

echo '== Reapply deployed 100269 Firestore hotfix state locally =='
python3 tools/hotfix_social_first_request_get_100269_2026_10_04.py
python3 tools/hotfix_social_list_query_100269_2026_10_04.py

echo '== Apply consolidated DEDA 100270 fixes =='
python3 tools/social_service_query_fix_100270_2026_10_04.py
python3 tools/admin_diamond_backend_100270_2026_10_04.py
python3 tools/admin_diamond_gift_ui_100270_2026_10_04.py
python3 tools/social_ui_wallet_fixes_100270_2026_10_04.py
python3 tools/settings_logout_100270_2026_10_04.py
python3 tools/firestore_social_admin_diamonds_100270_2026_10_04.py

echo '== Format only changed DEDA sources =='
dart format \
  lib/main.dart \
  lib/deda_social_service.dart \
  lib/deda_backend.dart \
  lib/admin_pages.dart

echo '== Validate DEDA 100270 consolidated requirements =='
python3 tools/validate_social_fixes_admin_gems_100270_2026_10_04.py

echo '== Revalidate critical proven DEDA invariants after 100270 =='
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

# The old 100260 diamond validator predates the server-gift augmentation. Its
# ad-scope safety remains covered above; 100270's validator explicitly checks
# that local rewarded diamonds are preserved and remote gifts stay separate.

echo '== Flutter analyzer: all changed sources =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/deda_social_service.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/deda_backend.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/admin_pages.dart
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo 'DEDA 100270 preflight completed successfully.'

if [[ "${DEDA_100270_PREFLIGHT_ONLY:-0}" == "1" ]]; then
  echo '100270 preflight-only mode: APK intentionally not built.'
  exit 0
fi

echo '== Build exactly one signed APK: DEDA 100270 =='
flutter build apk --release --build-number=100270 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100270 signed APK build completed successfully.'
