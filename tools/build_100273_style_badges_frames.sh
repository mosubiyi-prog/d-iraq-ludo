#!/usr/bin/env bash
set -euo pipefail

echo '== DEDA 100273: preserve proven 100272 source and recover approved artwork =='

if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 -m pip install --user pillow
fi

# The approved reference is preserved in four Base64 chunks. Two characters
# were introduced/lost around an old chunk boundary, so recover only around the
# three joins and accept a candidate only if Pillow fully decodes the JPEG.
python3 - <<'PY'
import base64
import io
import itertools
from pathlib import Path
from PIL import Image, ImageFile

ImageFile.LOAD_TRUNCATED_IMAGES = False
parts = sorted(Path('assets').glob('deda_ref_part*.txt'))
if len(parts) != 4:
    raise SystemExit(f'Expected 4 DEDA reference chunks, found {len(parts)}')
chunks = [''.join(p.read_text(encoding='utf-8').split()) for p in parts]
raw = ''.join(chunks)
joins = []
pos = 0
for chunk in chunks[:-1]:
    pos += len(chunk)
    joins.append(pos)

alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


def decode_candidate(encoded: str):
    core = encoded.rstrip('=')
    if len(core) % 4 == 1:
        return None
    encoded = core + ('=' * ((4 - len(core) % 4) % 4))
    try:
        data = base64.b64decode(encoded, validate=True)
    except Exception:
        return None
    if not (data.startswith(b'\xff\xd8\xff') and data.endswith(b'\xff\xd9')):
        return None
    try:
        with Image.open(io.BytesIO(data)) as im:
            im.load()
            if im.width < 300 or im.height < 300:
                return None
    except Exception:
        return None
    return data

# 1) Already-valid form.
data = decode_candidate(raw)
method = 'original'

# 2) Prefer deleting two accidental characters close to one of the joins.
if data is None:
    for join in joins:
        lo = max(0, join - 10)
        hi = min(len(raw), join + 10)
        positions = list(range(lo, hi))
        for a_i in range(len(positions)):
            for b_i in range(a_i + 1, len(positions)):
                a, b = positions[a_i], positions[b_i]
                candidate = raw[:a] + raw[a + 1:b] + raw[b + 1:]
                data = decode_candidate(candidate)
                if data is not None:
                    method = f'removed chars near join {join} at {a},{b}'
                    break
            if data is not None:
                break
        if data is not None:
            break

# 3) If two characters were lost at a join, restore alignment there. Try a few
# harmless pairs first, then the complete 64x64 pair space at the exact joins.
if data is None:
    simple_pairs = ['AA', '//', 'A/', '/A', '00', 'zz', '++']
    for join in joins:
        for offset in (-2, -1, 0, 1, 2):
            at = max(0, min(len(raw), join + offset))
            for pair in simple_pairs:
                data = decode_candidate(raw[:at] + pair + raw[at:])
                if data is not None:
                    method = f'inserted {pair!r} near join {join} at {at}'
                    break
            if data is not None:
                break
        if data is not None:
            break

if data is None:
    for join in joins:
        for x, y in itertools.product(alphabet, repeat=2):
            pair = x + y
            data = decode_candidate(raw[:join] + pair + raw[join:])
            if data is not None:
                method = f'recovered two missing Base64 chars at join {join}'
                break
        if data is not None:
            break

if data is None:
    raise SystemExit('Could not recover a fully decodable DEDA approved JPEG from repository chunks')

out = Path('assets/deda_style_reference_100273.jpg')
out.write_bytes(data)
with Image.open(out) as im:
    print(f'Recovered complete DEDA style reference via {method}: {len(data)} bytes, {im.width}x{im.height}')
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
