#!/usr/bin/env bash
set -euo pipefail
: "${DEDA_OWNED_APP:?}" "${DEDA_OWNED_PRIVATE:?}" "${DEDA_RULES_PRIVATE:?}" "${DEDA_RULES_PUBLIC:?}"
repo="$GITHUB_WORKSPACE"
pkg=dev.deda.qa.deda_owned_qa
node "$repo/tools/app_stability/rules_compat/emulator-check.cjs" > "$DEDA_OWNED_PRIVATE/node-policy-check.log" 2>&1
node "$repo/tools/app_stability/native_ownership/policy-server.cjs" > "$DEDA_OWNED_PRIVATE/fixture.log" 2>&1 &
fixture_pid=$!
cleanup(){ adb logcat -d -v threadtime > "$DEDA_OWNED_PRIVATE/native-logcat.log" 2>/dev/null || true; kill "$fixture_pid" 2>/dev/null || true; }
trap cleanup EXIT
python3 "$repo/tools/app_stability/native_ownership/wait-result.py" waiting --timeout 30
adb wait-for-device
test "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" = 36
adb uninstall "$pkg" >/dev/null 2>&1 || true
adb install -t "$DEDA_OWNED_APP/build/app/outputs/flutter-apk/app-debug.apk"
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_OWNED_PRIVATE/launch.log" 2>&1
python3 "$repo/tools/app_stability/native_ownership/wait-result.py" passed --timeout 240
python3 - <<'PY'
import json,os
from pathlib import Path
r=json.loads((Path(os.environ['DEDA_RULES_PUBLIC'])/'native-owned-result.json').read_text())
assert r['status']=='passed' and len(r['passed'])==10 and not r['failures']
assert r['originalDedaPinAuth'] and not r['privilegedIdentitySeeds'] and r['historyUnchangedVerified']
PY
