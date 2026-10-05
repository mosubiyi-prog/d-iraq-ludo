from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import math

ROOT = Path('.')
OUT = ROOT / 'assets' / 'deda_style'
OUT.mkdir(parents=True, exist_ok=True)

# DEDA 100273 deterministic artwork. These assets are generated locally during
# the build so the app no longer depends on a damaged binary reference file.
# Order must stay aligned with dedaStyleBadgeIds in lib/main.dart:
# member, spark, elite, royal, season1, legendary.
PALETTES = [
    ((54, 116, 181), (188, 224, 255), (238, 246, 255)),   # member
    ((0, 139, 191), (0, 229, 255), (211, 252, 255)),      # spark
    ((35, 35, 42), (217, 175, 76), (255, 235, 167)),      # elite
    ((89, 43, 145), (241, 184, 47), (255, 228, 137)),     # royal
    ((14, 116, 92), (226, 182, 64), (232, 255, 246)),     # season 1
    ((145, 24, 39), (247, 171, 48), (255, 225, 151)),     # legendary
]

S = 4
CANVAS = 256 * S
CENTER = CANVAS // 2


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def star_points(cx, cy, outer, inner, count=8, rotation=-math.pi / 2):
    pts = []
    for i in range(count * 2):
        r = outer if i % 2 == 0 else inner
        a = rotation + i * math.pi / count
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def regular_polygon(cx, cy, radius, sides, rotation=-math.pi / 2):
    return [
        (cx + math.cos(rotation + i * 2 * math.pi / sides) * radius,
         cy + math.sin(rotation + i * 2 * math.pi / sides) * radius)
        for i in range(sides)
    ]


def ring(draw, box, fill, width):
    draw.ellipse(box, outline=fill, width=width)


def downsample(img):
    return img.resize((256, 256), Image.Resampling.LANCZOS)


def save_png(img, path):
    # Keep alpha and enough detail for Flutter high-quality scaling.
    downsample(img).save(path, 'PNG', optimize=False)


def make_badge(index):
    dark, accent, light = PALETTES[index]
    img = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))

    # soft glow
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((175*S/4, 175*S/4, CANVAS-175*S/4, CANVAS-175*S/4), fill=rgba(accent, 115))
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    # bottom ribbon / tabs
    ribbon_y = int(CANVAS * 0.67)
    tab = int(CANVAS * 0.115)
    d.polygon([(CENTER-tab*2, ribbon_y), (CENTER-tab//2, ribbon_y), (CENTER-tab, CANVAS*0.91),
               (CENTER-tab*2.2, CANVAS*0.82)], fill=rgba(dark))
    d.polygon([(CENTER+tab*2, ribbon_y), (CENTER+tab//2, ribbon_y), (CENTER+tab, CANVAS*0.91),
               (CENTER+tab*2.2, CANVAS*0.82)], fill=rgba(dark))

    outer = int(CANVAS * 0.35)
    inner = int(CANVAS * 0.28)
    if index == 0:
        d.ellipse((CENTER-outer, CENTER-outer, CENTER+outer, CENTER+outer), fill=rgba(dark), outline=rgba(light), width=8*S)
    elif index == 1:
        d.polygon(star_points(CENTER, CENTER, outer, int(outer*0.78), 12), fill=rgba(dark))
        d.ellipse((CENTER-inner, CENTER-inner, CENTER+inner, CENTER+inner), fill=rgba(accent), outline=rgba(light), width=5*S)
    elif index == 2:
        d.polygon(regular_polygon(CENTER, CENTER, outer, 6), fill=rgba(dark), outline=rgba(accent))
        d.polygon(regular_polygon(CENTER, CENTER, int(outer*0.82), 6, rotation=0), outline=rgba(light), width=5*S)
    elif index == 3:
        d.polygon(star_points(CENTER, CENTER, outer, int(outer*0.70), 8), fill=rgba(dark))
        d.ellipse((CENTER-inner, CENTER-inner, CENTER+inner, CENTER+inner), fill=rgba((73, 29, 118)), outline=rgba(accent), width=7*S)
    elif index == 4:
        d.ellipse((CENTER-outer, CENTER-outer, CENTER+outer, CENTER+outer), fill=rgba(dark), outline=rgba(accent), width=8*S)
        # laurel leaves
        for side in (-1, 1):
            for j in range(5):
                y = CENTER + int((j-2)*0.075*CANVAS)
                x = CENTER + side*int((0.23 - abs(j-2)*0.012)*CANVAS)
                leaf = int(0.045*CANVAS)
                d.ellipse((x-leaf, y-leaf//2, x+leaf, y+leaf//2), fill=rgba(accent))
    else:
        # legendary flame-wing silhouette
        d.polygon(star_points(CENTER, CENTER, outer, int(outer*0.68), 10), fill=rgba(dark))
        for side in (-1, 1):
            wing = [
                (CENTER + side*inner//2, CENTER-int(0.08*CANVAS)),
                (CENTER + side*int(0.36*CANVAS), CENTER-int(0.23*CANVAS)),
                (CENTER + side*int(0.30*CANVAS), CENTER),
                (CENTER + side*int(0.40*CANVAS), CENTER+int(0.12*CANVAS)),
                (CENTER + side*inner//2, CENTER+int(0.10*CANVAS)),
            ]
            d.polygon(wing, fill=rgba(accent))
        d.ellipse((CENTER-inner, CENTER-inner, CENTER+inner, CENTER+inner), fill=rgba((113, 13, 26)), outline=rgba(light), width=6*S)

    # central DEDA diamond motif (no font dependency)
    diamond_r = int(CANVAS * 0.145)
    diamond = [(CENTER, CENTER-diamond_r), (CENTER+diamond_r, CENTER),
               (CENTER, CENTER+diamond_r), (CENTER-diamond_r, CENTER)]
    d.polygon(diamond, fill=rgba(accent), outline=rgba(light))
    small = int(diamond_r*0.50)
    d.polygon([(CENTER, CENTER-small), (CENTER+small, CENTER),
               (CENTER, CENTER+small), (CENTER-small, CENTER)], fill=rgba(light))
    d.ellipse((CENTER-int(CANVAS*.026), CENTER-int(CANVAS*.026),
               CENTER+int(CANVAS*.026), CENTER+int(CANVAS*.026)), fill=rgba(dark))

    return img


def make_frame(index):
    dark, accent, light = PALETTES[index]
    img = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))

    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    ring(gd, (80*S/4, 80*S/4, CANVAS-80*S/4, CANVAS-80*S/4), rgba(accent, 120), 18*S)
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    outer_margin = 25*S
    base_box = (outer_margin, outer_margin, CANVAS-outer_margin, CANVAS-outer_margin)
    ring(d, base_box, rgba(dark), 12*S)
    inset = 15*S
    ring(d, (outer_margin+inset, outer_margin+inset, CANVAS-outer_margin-inset, CANVAS-outer_margin-inset), rgba(accent), 9*S)
    inset2 = 28*S
    ring(d, (outer_margin+inset2, outer_margin+inset2, CANVAS-outer_margin-inset2, CANVAS-outer_margin-inset2), rgba(light), 4*S)

    # style-specific crown/top ornament
    top_y = 38*S
    if index in (2, 3, 5):
        crown_w = 70*S
        crown_h = 34*S
        crown = [
            (CENTER-crown_w, top_y+crown_h),
            (CENTER-crown_w, top_y+8*S),
            (CENTER-crown_w//2, top_y+22*S),
            (CENTER, top_y),
            (CENTER+crown_w//2, top_y+22*S),
            (CENTER+crown_w, top_y+8*S),
            (CENTER+crown_w, top_y+crown_h),
        ]
        d.polygon(crown, fill=rgba(accent), outline=rgba(light))
        for x in (CENTER-crown_w, CENTER, CENTER+crown_w):
            d.ellipse((x-7*S, top_y-7*S, x+7*S, top_y+7*S), fill=rgba(light))
    elif index == 1:
        d.polygon(star_points(CENTER, 52*S, 22*S, 10*S, 8), fill=rgba(accent), outline=rgba(light))
    elif index == 4:
        for side in (-1, 1):
            for j in range(4):
                x = CENTER + side*(42+j*17)*S
                y = (54+j*6)*S
                d.ellipse((x-14*S, y-7*S, x+14*S, y+7*S), fill=rgba(accent))
    else:
        d.polygon(regular_polygon(CENTER, 52*S, 18*S, 6), fill=rgba(accent), outline=rgba(light))

    # bottom gem and side accents
    gem_y = CANVAS - 45*S
    gem_r = 15*S
    d.polygon([(CENTER, gem_y-gem_r), (CENTER+gem_r, gem_y),
               (CENTER, gem_y+gem_r), (CENTER-gem_r, gem_y)], fill=rgba(accent), outline=rgba(light))
    for side in (-1, 1):
        for dy in (-45, 0, 45):
            x = CENTER + side*int(CANVAS*0.405)
            y = CENTER + dy*S
            r = 7*S if index < 4 else 9*S
            d.ellipse((x-r, y-r, x+r, y+r), fill=rgba(accent), outline=rgba(light))

    # Ensure the avatar opening is fully transparent and generous.
    hole = int(CANVAS * 0.295)
    d.ellipse((CENTER-hole, CENTER-hole, CENTER+hole, CENTER+hole), fill=(0, 0, 0, 0))
    return img


for i in range(6):
    save_png(make_badge(i), OUT / f'badge_{i}.png')
    save_png(make_frame(i), OUT / f'frame_{i}.png')

expected = [OUT / f'{kind}_{i}.png' for kind in ('badge', 'frame') for i in range(6)]
missing = [str(p) for p in expected if not p.exists() or p.stat().st_size < 2000]
if missing:
    raise SystemExit(f'100273 deterministic artwork generation incomplete: {missing}')

print('Generated 6 DEDA badges + 6 DEDA frames deterministically for 100273')
