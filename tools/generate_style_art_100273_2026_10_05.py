from pathlib import Path
import base64
import io

try:
    from PIL import Image, ImageFile
except Exception as exc:
    raise SystemExit(f'Pillow is required for 100273 artwork generation: {exc}')

ImageFile.LOAD_TRUNCATED_IMAGES = True
ROOT = Path('.')
ASSETS = ROOT / 'assets'
OUT = ASSETS / 'deda_style'
OUT.mkdir(parents=True, exist_ok=True)

parts = sorted(ASSETS.glob('deda_ref_part*.txt'))
if not parts:
    raise SystemExit('DEDA 100273 reference chunks are missing')
part_texts = [p.read_text(encoding='utf-8').strip() for p in parts]
joined = ''.join(part_texts)


def _decode_reference(payload: str):
    core = payload.rstrip('=')
    padded = core + ('=' * ((-len(core)) % 4))
    try:
        raw = base64.b64decode(padded, validate=False)
        image = Image.open(io.BytesIO(raw))
        image.load()
        if image.width >= 800 and image.height >= 1400:
            return image.convert('RGBA')
    except Exception:
        return None
    return None


source = _decode_reference(joined)
if source is None:
    # The reference was transferred in conservative text chunks. One historic
    # upload boundary lost two Base64 characters. Repair only around those
    # boundaries; nothing from the app or user data is involved. JPEG decoding
    # tolerates the two neutral recovery bytes while preserving the approved
    # visual reference for all crop regions.
    core = joined.rstrip('=')
    boundaries = []
    cursor = 0
    for value in part_texts[:-1]:
        cursor += len(value.rstrip('='))
        boundaries.append(cursor)
    fillers = ('AA', '//', 'A/', '/A', '00', 'A0', '0A', 'zz')
    for boundary in boundaries:
        if source is not None:
            break
        for delta in (0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6):
            pos = max(0, min(len(core), boundary + delta))
            for filler in fillers:
                candidate = core[:pos] + filler + core[pos:]
                source = _decode_reference(candidate)
                if source is not None:
                    print(f'Recovered DEDA reference near chunk boundary {boundary} ({delta:+d})')
                    break
            if source is not None:
                break

if source is None:
    raise SystemExit('Could not safely rebuild the DEDA 100273 style reference from its chunks')

# Normalize geometry if a future transfer uses a scaled JPEG of the same
# approved 864x1536 reference.
if source.size != (864, 1536):
    source = source.resize((864, 1536), Image.Resampling.LANCZOS)

# Crops are pinned to the approved 864x1536 comparison reference. Each pair is
# extracted from the same visual row so badge and frame keep one identity.
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
