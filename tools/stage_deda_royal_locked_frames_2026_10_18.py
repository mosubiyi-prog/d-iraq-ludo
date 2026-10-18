#!/usr/bin/env python3
"""DEDA point two: replace locked frame slots 3..5 only, preview before purchase.
Run after the exact verified 100342 source is reconstructed. No backend writes.
Requires user's exact original 850px images in assets/deda_royal_frames/.
"""
from pathlib import Path
import hashlib

MAIN=Path("lib/main.dart")
PUB=Path("pubspec.yaml")
DEST=Path("assets/deda_royal_frames")
MARKER="DEDA_ROYAL_LOCKED_FRAMES_2026_10_18"
ASSETS={
 "royal_frame_0.webp":(259300,"9ae19c51cbc7394299b361cb1f8dd07e015898b43e4ecaca0fdb0f4b207a12b5"),
 "royal_frame_1.webp":(260184,"a31029b56a4a989feaec25a119b58a8a90c378e6ba3159705d2d5e537f4f299e"),
 "royal_frame_2.webp":(247938,"dbd02ca458cf9e94e3a0005134d2b61cb0bdaaf7729893a8cbfe5f75123c249f"),
}
def replace_once(src, old, new, label):
    n=src.count(old)
    if n!=1: raise SystemExit(f"SAFE_STOP {label}: expected 1 anchor, saw {n}")
    return src.replace(old,new,1)

old=MAIN.read_text(encoding="utf-8")
pub=PUB.read_text(encoding="utf-8")
if MARKER in old or "DEDA_100342_POINT7_COMPACT_IDS_UI_ONLY" not in old or "DEDA_ROYAL_THREE_AVATARS_STEP1_2026_10_17" not in old or "DEDA_100343_STICKY_EDIT_PROFILE_PREVIEW" not in old:
    raise SystemExit("SAFE_STOP wrong base source or patch already applied")
for name,(length,digest) in ASSETS.items():
    path=DEST/name
    if not path.is_file():
        raise SystemExit("SAFE_STOP exact original frame missing: "+str(path))
    data=path.read_bytes()
    if len(data)!=length or hashlib.sha256(data).hexdigest()!=digest or data[:4]!=b"RIFF" or data[8:12]!=b"WEBP":
        raise SystemExit("SAFE_STOP source frame changed: "+name)

# The common frame renderer is used by edit previews and the live profile.
# Preserve legacy free frames 0..2 exactly by adding only an early branch.
start=old.index("class DedaFramedAvatar extends StatelessWidget {")
end=old.index("\nclass ",start+8)
section=old[start:end]
anchor="    final safeStyle = frameStyle.clamp(0, 5).toInt();\n    return SizedBox("
new_renderer=r'''    final safeStyle = frameStyle.clamp(0, 5).toInt();
    // DEDA_ROYAL_LOCKED_FRAMES_2026_10_18
    if (safeStyle >= 3) {
      return SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: size * 0.26,
              top: size * 0.292,
              width: size * 0.48,
              height: size * 0.325,
              child: ClipOval(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: DedaAvatarPortrait(
                    style: avatarStyle,
                    size: size * 0.48,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              // Lightweight thumbnails show the exact frame artwork without
              // three perpetual off-screen tickers in the selection gallery.
              // The pinned >=120px preview and actual profile still shimmer.
              child: size < 120.0
                  ? IgnorePointer(
                      child: Image.asset(
                        'assets/deda_royal_frames/royal_frame_' +
                            (safeStyle - 3).toString() + '.webp',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    )
                  : _DedaRoyalFrameMotion(
                      size: size,
                      asset: 'assets/deda_royal_frames/royal_frame_' +
                          (safeStyle - 3).toString() + '.webp',
                    ),
            ),
          ],
        ),
      );
    }
    return SizedBox('''
section=replace_once(section,anchor,new_renderer,"locked only renderer")
# Match the LAB motion: gentle 5.4-second wave on ornaments + five phased
# diamond glints. Both effects are clipped by the PNG/WebP ornament alpha.
# Neither portrait pixels nor actual frame geometry is animated.
motion = r'''
class _DedaRoyalFrameMotion extends StatefulWidget {
  final double size;
  final String asset;

  const _DedaRoyalFrameMotion({
    required this.size,
    required this.asset,
  });

  @override
  State<_DedaRoyalFrameMotion> createState() => _DedaRoyalFrameMotionState();
}

class _DedaRoyalFrameMotionState extends State<_DedaRoyalFrameMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Do not keep an infinite ticker running for reduced-motion users/tests.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Widget _diamondGlint(double phase, double px, double py, int index) {
    final point = (phase + index * 0.19) % 1.0;
    final rise = point < 0.5 ? point * 2.0 : (1.0 - point) * 2.0;
    final opacity = ((rise - 0.72) * 2.5).clamp(0.0, 0.60).toDouble();
    return Positioned(
      left: widget.size * (px - 0.037),
      top: widget.size * (py - 0.037),
      width: widget.size * 0.074,
      height: widget.size * 0.074,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Icon(
            Icons.auto_awesome,
            size: widget.size * 0.074,
            color: const Color(0xFFFDF6E5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Image.asset(
      widget.asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
    // Respect accessibility reduced motion.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return base;
    return AnimatedBuilder(
      animation: _motion,
      child: base,
      builder: (context, art) {
        final phase = _motion.value;
        return RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(child: art!),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.40,
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment(-2.9 + phase * 5.0, -1),
                        end: Alignment(-2.0 + phase * 5.0, 1),
                        colors: const <Color>[
                          Color(0x00FFFFFF),
                          Color(0xC0FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: const <double>[0, 0.50, 1],
                      ).createShader(bounds),
                      child: Image.asset(
                        widget.asset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
              _diamondGlint(phase, 0.50, 0.16, 0),
              _diamondGlint(phase, 0.22, 0.39, 1),
              _diamondGlint(phase, 0.78, 0.39, 2),
              _diamondGlint(phase, 0.50, 0.70, 3),
              _diamondGlint(phase, 0.69, 0.67, 4),
            ],
          ),
        );
      },
    );
  }
}
'''
text=old[:start]+section+motion+old[end:]

# Remove the opaque veil covering the image. Keep a small corner lock.
a=text.index("class DedaProfileFramePreview extends StatelessWidget {")
b=text.index("class DedaPreferences {",a)
preview=text[a:b]
start_lock=preview.index("          if (!free)\n            Positioned.fill(")
end_lock=preview.index("\n        ],\n      ),",start_lock)
preview=preview[:start_lock]+r'''          if (!free)
            PositionedDirectional(
              top: 5,
              start: 5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xE6FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFF986A32),
                  size: 16,
                ),
              ),
            ),'''+preview[end_lock:]
text=text[:a]+preview+text[b:]

# In edit page, tile tap affects *only preview*, not the persistent frame.
a=text.index("class _DedaEditProfilePageState extends State<DedaEditProfilePage> {")
b=text.index("class DedaAccountInfoPage extends StatefulWidget {",a)
edit=text[a:b]
edit=replace_once(edit,"  late int _frameStyle;\n","  late int _frameStyle;\n  int? _previewFrameStyle;\n","preview state")
edit=replace_once(edit,"frameStyle: _frameStyle,\n                  size: 126,","frameStyle: _previewFrameStyle ?? _frameStyle,\n                  size: 126,","fixed card preview")
edit=replace_once(edit,"final selected = free && _frameStyle == index;","final selected = _previewFrameStyle == index ||\n                        (_previewFrameStyle == null && free && _frameStyle == index);","selection")
edit=replace_once(edit,
"""onTap: free
                          ? () => setState(() => _frameStyle = index)
                          : _lockedFrameMessage,""",
"""onTap: free
                          ? () => setState(() {
                                _frameStyle = index;
                                _previewFrameStyle = null;
                              })
                          : () => setState(() => _previewFrameStyle = index),""",
"non-owning locked frame preview")
edit=replace_once(edit,
"return InkWell(\n                      onTap: free",
"return InkWell(\n                      key: ValueKey('deda_frame_slot_$index'),\n                      onTap: free",
"testable unchanged six frame slots")
edit=replace_once(edit,
"                                  : dedaText('مقفول', 'Locked'),",
"""                                  : (index == 3
                                      ? dedaText('زمردي ملكي', 'Royal emerald')
                                      : index == 4
                                          ? dedaText('ذهبي ملكي', 'Royal gold')
                                          : dedaText('وردي ملكي', 'Royal rose')),""",
"locked frame names")
notice="""            const SizedBox(height: 24),
            _sectionTitle(
              dedaText(
                'الخلفية من داخل DEDA',"""
edit=replace_once(edit,notice,"""            if (_previewFrameStyle != null)
              Padding(
                key: const Key('deda_locked_frame_preview_only_notice'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  dedaText(
                    'معاينة مجانية فقط. الإطار مقفول ولن يُحفظ أو يُخصم أي رصيد.',
                    'Free preview only. Locked frames are not saved or charged.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF775606)),
                ),
              ),
"""+notice,"preview disclosure")
if "frameStyle: _frameStyle," not in edit or "DedaDiamondsWallet.spend(" in edit or "DedaStyleInventory.addOwned(" in edit:
    raise SystemExit("SAFE_STOP wallet/save/inventory guard")
text=text[:a]+edit+text[b:]
if "DedaProfileFramePreview(" not in edit or "List<Widget>.generate(6, (index)" not in edit:
    raise SystemExit("SAFE_STOP existing six frame slots missing")

pub=replace_once(pub,"    - assets/deda_royal_avatars/deda_avatar_male_royal.jpg\n",
"    - assets/deda_royal_avatars/deda_avatar_male_royal.jpg\n"+
"".join("    - assets/deda_royal_frames/"+name+"\n" for name in ASSETS),
"approved image assets declaration")
MAIN.write_text(text,encoding="utf-8")
PUB.write_text(pub,encoding="utf-8")
print("PASS: same 6 frame slots, 3 exact user-supplied royal assets in locked 3..5")
print("PASS: all previews free, no wallet mutation, no saved locked frame")
