#!/usr/bin/env bash
set -euo pipefail

echo '== Save DEDA source files =='
cp lib/main.dart /tmp/main.dart
cp lib/traffic_quiz_page.dart /tmp/traffic_quiz_page.dart
cp pubspec.yaml /tmp/pubspec.yaml
cp deda_app_icon.png /tmp/deda_app_icon.png
cp google-services.json /tmp/google-services.json

echo '== Create clean Flutter Android project =='
flutter create . --org com.diraq.ludo --project-name d_iraq_ludo

echo '== Restore DEDA source files =='
cp /tmp/main.dart lib/main.dart
cp /tmp/traffic_quiz_page.dart lib/traffic_quiz_page.dart
cp /tmp/pubspec.yaml pubspec.yaml
cp /tmp/deda_app_icon.png deda_app_icon.png
cp /tmp/google-services.json android/app/google-services.json

echo '== Apply established DEDA release patches =='
python3 tools/final_release_fix_compat.py
python3 tools/final_release_fix.py
python3 tools/pin_login_patch.py
python3 tools/map_zoom_fix.py

echo '== Apply 100253 baseline =='
python3 tools/make_task_rewarded_patch_unique_2026_10_02.py
python3 tools/task_rewarded_ads_test_2026_10_02.py
python3 tools/rewarded_ads_startup_safety_fix_2026_10_02.py
python3 tools/rewarded_ads_diagnostic_error_details_2026_10_02.py
python3 tools/fix_daily_task_done_and_trip_1km_2026_10_02.py

echo '== Apply 100254 =='
python3 tools/fix_trip1km_progress_100254_2026_10_03.py
dart format lib/main.dart

echo '== Apply 100255 =='
python3 tools/fix_traffic_quiz_semantic_no_repeat_100255_2026_10_03.py
dart format lib/traffic_quiz_page.dart

echo '== Apply 100256 =='
python3 tools/fix_trip_progress_account_scope_100256_2026_10_03.py
dart format lib/main.dart

echo '== Configure Firebase Android AdMob launcher and signing =='
python3 tools/configure_rewarded_ads_android_build_2026_10_02.py

echo '== Apply real AdMob IDs 100257 =='
python3 tools/apply_real_admob_ids_100257_2026_10_03.py
dart format lib/main.dart

echo '== Apply 100258 =='
python3 tools/rewarded_ad_resilience_100258_2026_10_03.py
dart format lib/main.dart
python3 tools/validate_real_admob_100257_2026_10_03.py
python3 tools/validate_rewarded_ad_resilience_100258_2026_10_03.py

echo '== Apply 100259 diamonds =='
python3 tools/add_diamonds_reward_100259_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_diamonds_reward_100259_2026_10_04.py

echo '== Apply 100260 social hub =='
python3 tools/add_social_hub_phase1_100260_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_social_hub_phase1_100260_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100261 profile phase 2 =='
python3 tools/profile_phase2_100261_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_profile_phase2_100261_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100262 profile polish =='
python3 tools/profile_polish_100262_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_profile_polish_100262_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100263 stage cards =='
python3 tools/profile_stage_cards_fix_100263_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_profile_stage_cards_fix_100263_2026_10_04.py
python3 tools/validate_profile_polish_100262_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100264 points toggle =='
python3 tools/profile_points_toggle_100264_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_polish_100262_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100265 stat cards polish =='
python3 tools/profile_stat_cards_polish_100265_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100266 Friends page =='
python3 tools/friends_page_ui_100266_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_friends_page_ui_100266_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Apply 100267 Add Friend page + Friends search-line polish =='
python3 tools/add_friend_ui_100267_2026_10_04.py
dart format lib/main.dart
python3 tools/validate_add_friend_ui_100267_2026_10_04.py
python3 tools/validate_friends_page_ui_100266_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py

echo '== Android compatibility and image saving =='
python3 tools/apply_admob_android16_workmanager_fix_2026_10_02.py
python3 tools/android_media_save_patch.py

echo '== Restore and validate permanent signing key =='
python3 tools/restore_signing_key_2026_10_02.py
keytool -list -keystore android/app/deda-release.jks -storepass "$DEDA_STORE_PASSWORD" -alias "$DEDA_KEY_ALIAS" > /dev/null

echo '== Install dependencies and launcher icon =='
flutter pub add --dev flutter_launcher_icons
flutter pub get
dart run flutter_launcher_icons

echo '== Final 100267 source validation =='
python3 tools/validate_daily_tasks_card_sequence_2026_10_01.py
python3 tools/validate_prize_winners_flow_2026_10_01.py
python3 tools/validate_prize_cycle_complete_2026_10_01.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip1km_progress_100254_2026_10_03.py
python3 tools/validate_traffic_quiz_semantic_no_repeat_100255_2026_10_03.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py
python3 tools/validate_diamonds_after_social_hub_100260_2026_10_04.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_friends_page_ui_100266_2026_10_04.py
python3 tools/validate_add_friend_ui_100267_2026_10_04.py
grep -q "ca-app-pub-2512641627784244~4635932278" android/app/src/main/AndroidManifest.xml
grep -q "ca-app-pub-2512641627784244/6037567292" lib/main.dart
! grep -q "ca-app-pub-3940256099942544~3347511713" android/app/src/main/AndroidManifest.xml
! grep -q "ca-app-pub-3940256099942544/5224354917" lib/main.dart

echo '== Build signed APK 100267 =='
flutter build apk --release --build-number=100267 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100267 build completed successfully.'
