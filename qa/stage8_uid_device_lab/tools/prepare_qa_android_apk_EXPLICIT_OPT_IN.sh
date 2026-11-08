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

# A QA APK must use the EXACT dedicated test signing key enrolled in QA Firebase.
# Do not commit or send the keystore to GitHub. The file is operator-local.
if [[ -z "${DEDA_STAGE8_QA_SIGNING_KEYSTORE:-}" ]]; then
  echo "SAFE_STOP: dedicated QA signing keystore is required"; exit 7
fi
qa_signing_key="$(realpath -e "$DEDA_STAGE8_QA_SIGNING_KEYSTORE")"
case "$qa_signing_key/" in
  "$repo/"*) echo "SAFE_STOP: QA signing key must stay outside the repo"; exit 8;;
esac
qa_storepass="${DEDA_STAGE8_QA_STOREPASS:-android}"
qa_keypass="${DEDA_STAGE8_QA_KEYPASS:-android}"
expected_sha1="D7:7C:C5:49:40:B4:1D:BF:56:74:45:98:7A:1D:C9:EF:24:12:EB:39"
actual_sha1="$(keytool -list -v -keystore "$qa_signing_key" -alias androiddebugkey -storepass "$qa_storepass" 2>/dev/null | awk -F'SHA1: ' 'NF>1 {print $2; exit}')"
if [[ "$actual_sha1" != "$expected_sha1" ]]; then
  echo "SAFE_STOP: signing certificate does not match Firebase QA SHA-1"; exit 9
fi

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
# QA-only file picker requires Android SDK 36. This applies to the TEMP
# generated lab, never the original DEDA source, targetSdk or minSdk.
python3 - "$app/android/app" <<'PY'
from pathlib import Path
import sys
gradle = next(Path(sys.argv[1]).glob('build.gradle*'))
source = gradle.read_text()
assert 'compileSdk = flutter.compileSdkVersion' in source
gradle.write_text(source.replace('compileSdk = flutter.compileSdkVersion',
                                 'compileSdk = 36'))
PY
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
# Flutter's default debug key can differ by machine. Re-sign the built DEBUG
# APK using only the registered QA lab certificate, then verify before release.
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
apksigner_bin="$(command -v apksigner || true)"
if [[ -z "$apksigner_bin" && -n "$sdk_root" && -d "$sdk_root/build-tools" ]]; then
  apksigner_bin="$(find "$sdk_root/build-tools" -type f -name apksigner | sort -V | tail -n 1)"
fi
if [[ -z "$apksigner_bin" ]]; then
  echo "SAFE_STOP: Android SDK apksigner unavailable"; exit 10
fi
signed_apk="$workdir/QA-only-signed.apk"
"$apksigner_bin" sign --ks "$qa_signing_key" \
  --ks-key-alias androiddebugkey \
  --ks-pass "pass:$qa_storepass" --key-pass "pass:$qa_keypass" \
  --out "$signed_apk" "$apk"
"$apksigner_bin" verify --verbose --print-certs "$signed_apk" > "$workdir/qa-signature-verify.txt"
verified_sha1="$(awk -F': ' '/Signer #1 certificate SHA-1 digest:/ {print toupper($2); exit}' "$workdir/qa-signature-verify.txt")"
if [[ "$verified_sha1" != "${expected_sha1//:/}" ]]; then
  echo "SAFE_STOP: signed APK certificate does not match registered QA SHA-1"; exit 11
fi
dest="$outdir/DEDA-UID-QA-LAB-ONLY-DEBUG.apk"
cp "$signed_apk" "$dest"
sha256sum "$dest"
echo "PASS_QA_APK_DEBUG_SIGNED_WITH_VERIFIED_QA_CERT_NO_PRODUCTION_NO_PLAY"
