#!/usr/bin/env bash
set -euo pipefail
: "${DEDA_NATIVE_APP:?}" "${DEDA_NATIVE_RESULTS:?}"
repo="$GITHUB_WORKSPACE"
pkg=dev.deda.qa.deda_transport_qa
mkdir -p "$DEDA_NATIVE_RESULTS"
node "$repo/tools/app_stability/native_transport/fixture-server.cjs" > "$DEDA_NATIVE_RESULTS/fixture.log" 2>&1 &
fixture_pid=$!
cleanup() {
  adb logcat -d -v threadtime > "$DEDA_NATIVE_RESULTS/native-logcat.log" 2>/dev/null || true
  kill "$fixture_pid" 2>/dev/null || true
}
trap cleanup EXIT
python3 "$repo/tools/app_stability/native_transport/wait-result.py" waiting --timeout 30
adb wait-for-device
test "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" = 36
adb uninstall "$pkg" > /dev/null 2>&1 || true
adb install -t "$DEDA_NATIVE_APP/build/app/outputs/flutter-apk/app-debug.apk"
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_NATIVE_RESULTS/first-launch.log" 2>&1
python3 "$repo/tools/app_stability/native_transport/wait-result.py" background-ready --timeout 240
background_pid="$(adb shell pidof "$pkg" | tr -d '\r')"
test -n "$background_pid"
adb shell input keyevent KEYCODE_HOME
python3 "$repo/tools/app_stability/native_transport/wait-result.py" backgrounded --timeout 30
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_NATIVE_RESULTS/resume-launch.log" 2>&1
python3 "$repo/tools/app_stability/native_transport/wait-result.py" restart-ready --timeout 180
first_pid="$(adb shell pidof "$pkg" | tr -d '\r')"
test -n "$first_pid"
test "$background_pid" = "$first_pid"
printf '%s\n%s\n' "$background_pid" "$first_pid" > "$DEDA_NATIVE_RESULTS/same-process-background-pids.txt"
adb shell am force-stop "$pkg"
test -z "$(adb shell pidof "$pkg" | tr -d '\r')"
# Same installed APK and Android data directory. No adb clear/uninstall, SDK
# reload or preferences mock between these two distinct native processes.
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > "$DEDA_NATIVE_RESULTS/second-launch.log" 2>&1
python3 "$repo/tools/app_stability/native_transport/wait-result.py" passed --timeout 180
second_pid="$(adb shell pidof "$pkg" | tr -d '\r')"
test -n "$second_pid"
test "$first_pid" != "$second_pid"
printf '%s\n%s\n' "$first_pid" "$second_pid" > "$DEDA_NATIVE_RESULTS/distinct-process-pids.txt"
adb logcat -d -v threadtime > "$DEDA_NATIVE_RESULTS/native-logcat.log"
awk -v a="$first_pid" -v b="$second_pid" '$3 == a || $3 == b' "$DEDA_NATIVE_RESULTS/native-logcat.log" > "$DEDA_NATIVE_RESULTS/app-process-logcat.log"
if rg -n 'FATAL EXCEPTION|Unhandled Exception|MissingPluginException|NoSuchMethodError|ClassNotFoundException|\[ERROR:flutter' "$DEDA_NATIVE_RESULTS/app-process-logcat.log"; then
  exit 70
fi
