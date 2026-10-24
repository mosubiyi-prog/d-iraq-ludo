#!/usr/bin/env bash
set -euo pipefail
: "${DEDA_PIN_APP:?}" "${DEDA_PIN_PRIVATE:?}" "${DEDA_RULES_PRIVATE:?}" "${DEDA_RULES_PUBLIC:?}"
repo="$GITHUB_WORKSPACE"
pkg=dev.deda.qa.deda_auth_qa
# Original/merged policy comparison is required before accepting native tests.
node "$repo/tools/app_stability/rules_compat/emulator-check.cjs" > "$DEDA_PIN_PRIVATE/node-policy-check.log" 2>&1
node "$repo/tools/app_stability/native_auth/policy-server.cjs" > "$DEDA_PIN_PRIVATE/policy-server.log" 2>&1 &
fixture_pid=$!
cleanup() {
  adb logcat -d -v threadtime > "$DEDA_PIN_PRIVATE/native-logcat.log" 2>/dev/null || true
  kill "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT
python3 "$repo/tools/app_stability/native_auth/wait-result.py" waiting --timeout 30
adb wait-for-device
test "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" = 36
adb uninstall "$pkg" > /dev/null 2>&1 || true
adb install -t "$DEDA_PIN_APP/build/app/outputs/flutter-apk/app-debug.apk"
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_PIN_PRIVATE/first-launch.log" 2>&1
python3 "$repo/tools/app_stability/native_auth/wait-result.py" restart-ready --timeout 240
first_pid="$(adb shell pidof "$pkg" | tr -d '\r')"
test -n "$first_pid"
adb shell am force-stop "$pkg"
test -z "$(adb shell pidof "$pkg" | tr -d '\r')"
# Same binary and native data; no clear/uninstall/preferences mock here.
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_PIN_PRIVATE/second-launch.log" 2>&1
python3 "$repo/tools/app_stability/native_auth/wait-result.py" passed --timeout 180
second_pid="$(adb shell pidof "$pkg" | tr -d '\r')"
test -n "$second_pid"
test "$first_pid" != "$second_pid"
printf '%s\n%s\n' "$first_pid" "$second_pid" > "$DEDA_PIN_PRIVATE/process-pids.txt"
adb logcat -d -v threadtime > "$DEDA_PIN_PRIVATE/native-logcat.log"
awk -v a="$first_pid" -v b="$second_pid" '$3 == a || $3 == b' "$DEDA_PIN_PRIVATE/native-logcat.log" > "$DEDA_PIN_PRIVATE/app-process-logcat.log"
if rg -n 'FATAL EXCEPTION|Unhandled Exception|MissingPluginException|NoSuchMethodError|ClassNotFoundException|\[ERROR:flutter' "$DEDA_PIN_PRIVATE/app-process-logcat.log"; then
  exit 70
fi
python3 - <<'PY'
import json,os
from pathlib import Path
private,public=Path(os.environ['DEDA_PIN_PRIVATE']),Path(os.environ['DEDA_RULES_PUBLIC'])
p=public/'native-pin-result.json';r=json.loads(p.read_text())
assert r['status']=='passed' and len(r['passed'])==20 and not r['failures']
pids=(private/'process-pids.txt').read_text().split()
assert len(pids)==2 and all(p.isdigit() for p in pids) and pids[0]!=pids[1]
r.update(coldRestart=True,firstProcessPid=pids[0],secondProcessPid=pids[1],
 nativeProcessErrorsAbsent=True,actualNativeAuthCases=13,nativePlaceRecoveryCases=7,nativeTotalCases=20)
p.write_text(json.dumps(r,indent=2)+'\n')
PY
