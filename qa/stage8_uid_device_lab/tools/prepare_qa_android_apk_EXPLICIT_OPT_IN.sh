#!/usr/bin/env bash
# Stage 8 separate test app build script. DO NOT run on the production project.
# No Firebase project creation, no Firebase deploy, no Google Play action.
# Does not install on a device automatically. Creates a QA APK ONLY after
# explicit operator opt-in and a distinct QA Firebase configuration file.
set -euo pipefail

if [[ "${DEDA_STAGE8_OWNER_APPROVED_QA_BUILD:-}" != "YES_STAGE8_QA_ONLY" ]]; then
  echo "SAFE_STOP: QA build not separately approved"; exit 2
fi
if [[ $# -ne 2 ]]; then
  echo "Usage: prepare_qa_android_apk_EXPLICIT_OPT_IN.sh /outside/repo/qa.json /outside/repo/output"
  exit 2
fi
repo="$(git rev-parse --show-toplevel)"
source_dir="$repo/qa/stage8_uid_device_lab"
config="$1"
outdir="$2"
python3 "$source_dir/tools/preflight_qa_config.py" \
  --config "$config" --repo-root "$repo" \
  --android-package com.deda.qa.uiddevice

# QA build output and config MUST NOT be in the source repository.
mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd -P)"
case "$outdir/" in "$repo/"*) echo "SAFE_STOP: output must be outside repo"; exit 3;; esac

# Create Android source from a fresh Flutter generated test package in temp.
# No copy of production Android, main.dart, google-services.json or sign key.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
flutter create --platforms=android \
  --org com.deda.qa --project-name uiddevice "$workdir/uiddevice"
app="$workdir/uiddevice"
cp "$source_dir/pubspec.yaml" "$app/pubspec.yaml"
cp "$source_dir/lib/"*.dart "$app/lib/"
mkdir -p "$app/test"
rm -f "$app/test/widget_test.dart"
cp "$source_dir/test/"*.dart "$app/test/"

# Check the ACTUAL generated Android package, not a client-supplied label.
if ! grep -qE 'applicationId[[:space:]]*=?[[:space:]]*"com\.deda\.qa\.uiddevice"' \
  "$app"/android/app/build.gradle*; then
  echo "SAFE_STOP: generated Android package was not the isolated QA id"; exit 4
fi
if [[ -f "$app/android/app/google-services.json" ||
      -f "$app/google-services.json" ]]; then
  echo "SAFE_STOP: unexpected Firebase google-services.json in QA build"; exit 5
fi
python3 - "$app/android/app/src/main/AndroidManifest.xml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
text=p.read_text()
text=text.replace('android:label="uiddevice"',
                  'android:label="DEDA UID LAB - TEST ONLY"')
assert 'android:label="DEDA UID LAB - TEST ONLY"' in text
p.write_text(text)
PY

(
  cd "$app"
  flutter pub get
  dart analyze --fatal-infos lib/ test/
  flutter test --no-pub
  flutter build apk --debug --dart-define-from-file="$config"
)
apk="$app/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$apk"
dest="$outdir/DEDA-UID-QA-LAB-ONLY-DEBUG.apk"
cp "$apk" "$dest"
sha256sum "$dest"
echo "PASS_QA_APK_DEBUG_ONLY_NO_PRODUCTION_FIREBASE_NO_APP_INSTALL_NO_PLAY"
