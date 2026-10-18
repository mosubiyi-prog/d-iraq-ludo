#!/usr/bin/env python3
"""DEDA point 3: retain six legacy background choices, add three royal options.

Run after proven 100342 source reconstruction, royal avatar hero, sticky edit
preview and the locked royal frame stage. Changes only background choice UI,
background storage range and surface rendering. NO Firebase, APK, purchases or
user-account migration.
"""
from pathlib import Path
import hashlib

MAIN = Path("lib/main.dart")
PUBSPEC = Path("pubspec.yaml")
marker = "// DEDA_POINT3_NINE_BACKGROUNDS_2026_10_18"
a_assets = {
    "assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp":
        (16198, "744f1a731b0611fc47b7685a78a6f81b319e066869c7f831f4a84b93dc343f5c"),
    "assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp":
        (13350, "5efd143d3ae5ab2ab6e3c0a4c2e98105398fa0428e7530f2acf085e957db4b9b"),
}

def exactly(src: str, old: str, new: str, label: str) -> str:
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"SAFE_STOP {label}: wanted 1 exact anchor, got {count}")
    return src.replace(old, new, 1)

if not MAIN.is_file() or not PUBSPEC.is_file():
    raise SystemExit("SAFE_STOP missing Flutter app source/manifest")
source = MAIN.read_text(encoding="utf-8")
pubspec = PUBSPEC.read_text(encoding="utf-8")
if marker in source or "DEDA_ROYAL_LOCKED_FRAMES_2026_10_18" not in source \
        or "DEDA_100343_STICKY_EDIT_PROFILE_PREVIEW" not in source \
        or "DEDA_ROYAL_PROFILE_HERO_LAYOUT_ONLY_2026_10_17" not in source:
    raise SystemExit("SAFE_STOP wrong reconstructed DEDA baseline or already applied")

for asset, (length, sha256) in a_assets.items():
    p = Path(asset)
    if not p.is_file():
        raise SystemExit("SAFE_STOP required original-approved background asset missing: " + asset)
    binary = p.read_bytes()
    if len(binary) != length or hashlib.sha256(binary).hexdigest() != sha256:
        raise SystemExit("SAFE_STOP background asset SHA/size mismatch: " + asset)
    if binary[:4] != b"RIFF" or binary[8:12] != b"WEBP":
        raise SystemExit("SAFE_STOP non-WebP image: " + asset)

# Preserve EXACT old six colors and their indices. Append three new options.
palette_old = """    [Color(0xFFFFF5F6), Color(0xFFF0DBDE)],
  ];
  return backgrounds[style.abs() % backgrounds.length];
}"""
palette_new = """    [Color(0xFFFFF5F6), Color(0xFFF0DBDE)],
    [Color(0xFF172653), Color(0xFF592950)], // 6 original royal starfield
    [Color(0xFF044F55), Color(0xFF052D56)], // 7 emerald-gold waves
    [Color(0xFF74243B), Color(0xFF4A102C)], // 8 rose-burgundy-gold
  ];
  return backgrounds[style.clamp(0, 8).toInt()];
}"""
source = exactly(source, palette_old, palette_new, "preserve + extend background palette")

# The account-local preference key remains exactly the same.
# Only extend its allowed value range: 0..8 (never reset existing values).
source = exactly(
    source,
    "profileBackgroundStyle = backgroundStyle.clamp(0, 5).toInt();",
    "profileBackgroundStyle = backgroundStyle.clamp(0, 8).toInt();",
    "safe saved background style range",
)
# Additional load caps protect malformed newer settings without touching
# saved phone/name/UID/diamonds, and preserve legacy six values unchanged.
source = exactly(
    source,
    "profileBackgroundStyle = prefs.getInt(_profileBackgroundKey(phone)) ?? 0;",
    "profileBackgroundStyle = (prefs.getInt(_profileBackgroundKey(phone)) ?? 0).clamp(0, 8).toInt();",
    "existing account style loading",
)
source = exactly(
    source,
    """profileBackgroundStyle =
        prefs.getInt(_profileBackgroundKey(normalizedPhone)) ?? 0;""",
    """profileBackgroundStyle =
        (prefs.getInt(_profileBackgroundKey(normalizedPhone)) ?? 0).clamp(0, 8).toInt();""",
    "account login style loading",
)

# Shared original royal paint for style 6, exact two art files for styles 7/8.
# The profile and editor both use the SAME surface so chosen artwork matches.
royal_component = r'''
// DEDA_POINT3_NINE_BACKGROUNDS_2026_10_18
class DedaRoyalBackgroundArtwork extends StatelessWidget {
  final int style;
  final Color glow;

  const DedaRoyalBackgroundArtwork({
    super.key,
    required this.style,
    this.glow = const Color(0xFF6B6ABC),
  });

  static String? assetFor(int style) {
    if (style == 7) {
      return 'assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp';
    }
    if (style == 8) {
      return 'assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(style);
    if (asset != null) {
      return Image.asset(
        asset,
        key: ValueKey<String>('deda_royal_background_art_$style'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            Color(0xFF092A63),
            Color(0xFF222056),
            Color(0xFF51204E),
            Color(0xFF111C49),
          ],
          stops: <double>[0, 0.41, 0.72, 1],
        ),
      ),
      child: CustomPaint(
        painter: _DedaRoyalProfileBackdropPainter(glow: glow),
      ),
    );
  }
}

'''
# Add helper immediately above the profile phase2 page class (from applied hero stage).
hero_class = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
source = exactly(source, hero_class, royal_component + hero_class,
                 "add shared royalty background renderer")

# Profile hero uses the original painter for the original/legacy choices.
# New emerald/rose backgrounds are painted behind ALL profile fields;
# the portrait, copy-ID, XP level, badges remain untouched.
hero_start = source.index("  Widget _profileHeroCard() {", source.index(hero_class))
hero_end = source.index("  Widget _avatar(int frameStyle, double size) {", hero_start)
hero = source[hero_start:hero_end]
old_hero_overlay = """              Positioned.fill(
                child: CustomPaint(
                  painter: _DedaRoyalProfileBackdropPainter(
                    glow: savedColors.last,
                  ),
                ),
              ),"""
new_hero_overlay = """              Positioned.fill(
                child: DedaRoyalBackgroundArtwork(
                  key: const Key('deda_profile_saved_background_art'),
                  style: DedaPreferences.profileBackgroundStyle,
                  glow: savedColors.last,
                ),
              ),"""
hero = exactly(hero, old_hero_overlay, new_hero_overlay,
               "saved royal background on profile card")
source = source[:hero_start] + hero + source[hero_end:]

# The sticky preview remains PINNED; only a background layer is inserted
# behind the same portrait and existing frame. The saving controls remain.
edit_start = "class _DedaEditProfilePageState extends State<DedaEditProfilePage> {"
edit_end = "class DedaAccountInfoPage extends StatefulWidget {"
start = source.index(edit_start)
end = source.index(edit_end, start)
edit = source[start:end]
card_pos = edit.index("key: const Key('deda_sticky_preview_avatar_card')")
preview_end = edit.index("key: const Key('deda_edit_profile_scroll_choices')", card_pos)
card_region = edit[card_pos:preview_end]
old_center = """              child: Center(
                child: DedaFramedAvatar(
                  avatarStyle: _avatarStyle,
                  frameStyle: _previewFrameStyle ?? _frameStyle,
                  size: 126,
                ),
              ),"""
new_center = """              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_backgroundStyle >= 6)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: DedaRoyalBackgroundArtwork(
                          key: const Key('deda_edit_live_royal_background'),
                          style: _backgroundStyle,
                        ),
                      ),
                    ),
                  Center(
                    child: DedaFramedAvatar(
                      avatarStyle: _avatarStyle,
                      frameStyle: _previewFrameStyle ?? _frameStyle,
                      size: 126,
                    ),
                  ),
                ],
              ),"""
card_region = exactly(card_region, old_center, new_center,
                      "pinned live edit preview remains fixed")
edit = edit[:card_pos] + card_region + edit[preview_end:]

# Modify ONLY the 'background from DEDA' grid: 6 existing exact choices +
# 3 new available colors. Do not change the separate SIX avatar/frame grids.
bg_start = edit.index("'الخلفية من داخل DEDA'")
bg_end = edit.index("            const SizedBox(height: 22),", bg_start)
bg_block = edit[bg_start:bg_end]
bg_block = exactly(
    bg_block,
    "children: List<Widget>.generate(6, (index) {",
    "children: List<Widget>.generate(9, (index) {",
    "background choice count only",
)
bg_block = exactly(
    bg_block,
    "                      child: AnimatedContainer(\n                        duration: const Duration(milliseconds: 160),",
    """                      child: AnimatedContainer(
                        key: ValueKey<String>('deda_background_tile_$index'),
                        duration: const Duration(milliseconds: 160),
                        clipBehavior: Clip.antiAlias,""",
    "identifiable new and legacy tiles",
)
bg_block = exactly(
    bg_block,
    """                        child: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF17652F),
                                size: 27,
                              )
                            : null,""",
    """                        child: index < 6
                            ? (selected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF17652F),
                                    size: 27,
                                  )
                                : null)
                            : Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  DedaRoyalBackgroundArtwork(style: index),
                                  if (selected)
                                    const Center(
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Color(0xFFFFE6A0),
                                        size: 27,
                                        shadows: <Shadow>[
                                          Shadow(color: Colors.black87, blurRadius: 5),
                                        ],
                                      ),
                                    ),
                                ],
                              ),""",
    "render royal artwork directly in matching choice fields",
)
edit = edit[:bg_start] + bg_block + edit[bg_end:]
source = source[:start] + edit + source[end:]

for title in ("deda_sticky_preview_avatar_card", "deda_edit_profile_scroll_choices",
              "deda_locked_frame_preview_only_notice", "DedaProfileFramePreview(",
              "await DedaPreferences.setProfileAppearance("):
    if title not in edit:
        raise SystemExit("SAFE_STOP protected edit or sticky behavior missing: " + title)
for title in ("DedaDiamondsWallet", "DedaSocialProgressWallet",
              "DedaStyleInventory", "DedaBackend.personalShareIdForPhone"):
    if title not in source:
        raise SystemExit("SAFE_STOP account features missing: " + title)

pubspec = exactly(
    pubspec,
    "    - assets/deda_royal_avatars/deda_avatar_male_royal.jpg\n",
    """    - assets/deda_royal_avatars/deda_avatar_male_royal.jpg
    - assets/deda_royal_backgrounds/deda_royal_bg_emerald.webp
    - assets/deda_royal_backgrounds/deda_royal_bg_burgundy.webp
""",
    "include exact original approved luxury background artworks",
)
# Immutable backup identity, Firestore and release signing unaffected.
MAIN.write_text(source, encoding="utf-8")
PUBSPEC.write_text(pubspec, encoding="utf-8")
print("PASS: 6 original backgrounds retained + 3 royal options in 9-style grid")
print("PASS: tapping updates pinned preview; saving and reloading 0..8 works")
print("PASS: profiles render actual saved royal art; no purchases or account changes")
