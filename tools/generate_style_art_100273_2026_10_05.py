from pathlib import Path
import base64
import io

try:
    from PIL import Image
except Exception as exc:
    raise SystemExit(f'Pillow is required for 100273 artwork generation: {exc}')

ROOT = Path('.')
ASSETS = ROOT / 'assets'
OUT = ASSETS / 'deda_style'
OUT.mkdir(parents=True, exist_ok=True)

parts = sorted(ASSETS.glob('deda_ref_part*.txt'))
if not parts:
    raise SystemExit('DEDA 100273 reference chunks are missing')
raw_b64 = ''.join(p.read_text(encoding='utf-8').strip() for p in parts)
try:
    raw = base64.b64decode(raw_b64)
    source = Image.open(io.BytesIO(raw)).convert('RGBA')
except Exception as exc:
    raise SystemExit(f'Could not rebuild DEDA style reference: {exc}')

if source.size[0] < 800 or source.size[1] < 1400:
    raise SystemExit(f'Unexpected DEDA reference size: {source.size}')

# Crops are pinned to the approved 864x1536 comparison reference.
# Each pair is intentionally extracted from the same visual row so the badge
# and frame preserve one matching identity.
badge_boxes = [
    (245, 140, 442, 292),
    (245, 350, 442, 505),
    (245, 558, 442, 723),
    (245, 775, 442, 935),
    (235, 995, 442, 1175),
    (235, 1255, 442, 1430),
]
frame_boxes = [
    (485, 140, 705, 312),
    (475, 350, 705, 528),
    (470, 560, 705, 748),
    (470, 775, 705, 958),
    (470, 995, 710, 1202),
    (470, 1245, 710, 1450),
]

def _soft_remove_neutral_background(im: Image.Image) -> Image.Image:
    px = im.load()
    width, height = im.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = px[x, y]
            mn = min(r, g, b)
            mx = max(r, g, b)
            saturation = mx - mn
            if mn >= 248 and saturation <= 10:
                alpha = 0
            elif mn >= 238 and saturation <= 16:
                alpha = max(0, min(255, int((248 - mn) / 10 * 255)))
            else:
                alpha = a
            px[x, y] = (r, g, b, alpha)
    return im

def _cut_avatar_opening(im: Image.Image) -> Image.Image:
    px = im.load()
    width, height = im.size
    cx = width * 0.50
    cy = height * 0.49
    rx = width * 0.235
    ry = height * 0.275
    for y in range(height):
        for x in range(width):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d <= 1.0:
                r, g, b, a = px[x, y]
                # Feather only the final 20% of the opening edge so there is
                # no visible hard cut around the user's avatar.
                edge = max(0.0, min(1.0, (d - 0.80) / 0.20))
                px[x, y] = (r, g, b, int(a * edge))
    return im

def _export(box, target: Path, opening: bool) -> None:
    crop = source.crop(box)
    new_width = 180
    new_height = round(crop.height * new_width / crop.width)
    crop = crop.resize((new_width, new_height), Image.Resampling.LANCZOS)
    crop = _soft_remove_neutral_background(crop)
    if opening:
        crop = _cut_avatar_opening(crop)
    crop.save(target, 'PNG', optimize=True)

for index, box in enumerate(badge_boxes):
    _export(box, OUT / f'badge_{index}.png', False)
for index, box in enumerate(frame_boxes):
    _export(box, OUT / f'frame_{index}.png', True)

expected = [OUT / f'{kind}_{index}.png' for kind in ('badge', 'frame') for index in range(6)]
missing = [str(p) for p in expected if not p.exists() or p.stat().st_size < 2000]
if missing:
    raise SystemExit(f'100273 artwork generation incomplete: {missing}')

print('Generated 6 matched DEDA badges + 6 matched DEDA frames for 100273')
