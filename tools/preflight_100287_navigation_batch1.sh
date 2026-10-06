#!/usr/bin/env bash
set -euo pipefail

echo '== Reconstruct proven DEDA 100286 without producing an APK =='
awk '/== Flutter analyzer ==/{exit} {print}' tools/build_100286_navigation_seven_fixes.sh | bash

echo '== Apply DEDA 100287 navigation batch 1 =='
python3 tools/navigation_batch1_100287.py
dart format lib/main.dart

echo '== Validate 100286 invariants are still intact =='
python3 tools/validate_navigation_seven_fixes_100286.py

echo '== Validate 100287 batch 1 =='
python3 tools/validate_navigation_batch1_100287.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/deda_team_page.dart lib/admin_pages.dart

echo 'DEDA 100287 navigation batch1 preflight completed successfully.'
