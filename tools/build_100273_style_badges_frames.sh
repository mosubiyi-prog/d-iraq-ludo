#!/usr/bin/env bash
set -euo pipefail

echo '== DEDA 100273: preserve proven 100272 source and restore approved artwork =='

# GitHub-hosted runners may not have Pillow preinstalled. Install it only when
# needed; this happens before deterministic local artwork extraction.
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 -m pip install --user pillow
fi

# The complete approved visual reference is already preserved in four text
# chunks under assets/. Reassemble those exact chunks into the JPEG used by the
# deterministic badge/frame cropper. This avoids binary corruption in the repo.
python3 - <<'PY'
import base64
from pathlib import Path

parts = sorted(Path('assets').glob('deda_ref_part*.txt'))
if len(parts) != 4:
    raise SystemExit(f'Expected 4 DEDA reference chunks, found {len(parts)}')
encoded = ''.join(p.read_text(encoding='utf-8').strip() for p in parts)
try:
    data = base64.b64decode(encoded, validate=True)
except Exception as exc:
    raise SystemExit(f'Could not decode complete DEDA reference chunks: {exc}')
if not data.startswith(b'\xff\xd8\xff') or not data.endswith(b'\xff\xd9'):
    raise SystemExit('Reassembled DEDA reference is not a complete JPEG')
out = Path('assets/deda_style_reference_100273.jpg')
out.write_bytes(data)
print(f'Restored complete DEDA style reference: {len(data)} bytes')
PY

python3 tools/generate_style_art_100273_2026_10_05.py
python3 tools/style_badges_frames_100273_2026_10_05.py

echo '== Format only the source changed by 100273 =='
dart format lib/main.dart

echo '== Validate 100273 contract =='
python3 tools/validate_style_badges_frames_100273_2026_10_05.py

echo '== Revalidate critical earlier invariants =='
python3 tools/validate_gifts_friends_v1_100271_2026_10_05.py
python3 tools/validate_profile_points_toggle_100264_2026_10_04.py
python3 tools/validate_profile_stat_cards_polish_100265_2026_10_04.py
python3 tools/validate_rewarded_ads_scope_2026_10_02.py
python3 tools/validate_trip_progress_account_scope_100256_2026_10_03.py

echo '== Flutter analyzer =='
flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart

echo '== Build exactly one signed APK: DEDA 100273 =='
flutter build apk --release --build-number=100273 --dart-define=USE_NEXT_GEN_SDK=true

echo 'DEDA 100273 signed APK build completed successfully.'
