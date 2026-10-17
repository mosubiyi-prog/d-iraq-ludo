#!/usr/bin/env python3
"""DEDA 100344: exact owner royal transparent frames, preview-only + shimmer.

Only edit the frames renderer, EDIT PROFILE presentation, and pubspec assets.
Never add prices, purchases, ownership, wallet writes, ID switch or Firebase IO.
This stage runs AFTER Point7 and the sticky-preview 100343 stage.
"""
from pathlib import Path
import hashlib

path=Path("lib/main.dart")
manifest=Path("pubspec.yaml")
s=path.read_text(encoding="utf-8")
pub=manifest.read_text(encoding="utf-8")
marker="// DEDA_100344_OWNER_EXACT_ROYAL_FRAMES_PREVIEW_ONLY"
assert marker not in s
assert "DEDA_100343_STICKY_EDIT_PROFILE_PREVIEW" in s
expected={
 "deda_frame_gold_royal.webp":("78d9974884b368e0225f34b184c7d39d33ea1b6c",260184),
 "deda_frame_ruby_royal.webp":("0806eeb07038b8eb501e29fd34b8f90b893b6f3e",247938),
 "deda_frame_emerald_royal.webp":("7eb392719a9448d71a5f73ce425f9382b5769bf2",259300),
}
for name,(blob,sz) in expected.items():
 f=Path("assets/deda_royal_frames")/name
 assert f.is_file(), "SAFE_STOP missing ORIGINAL owner frame: "+str(f)
 data=f.read_bytes()
 git_blob=hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
 assert len(data)==sz and git_blob==blob and data[:4]==b"RIFF" and data[8:12]==b"WEBP", "SAFE_STOP asset modified: "+name

def exactly(source,old,new,label):
 count=source.count(old)
 assert count==1, f"SAFE_STOP {label}: expected one, found {count}"
 return source.replace(old,new,1)

# Existing 0/1/2 frames stay byte-for-byte identical; new 3/4/5 use
# original owner WebPs. Measured central alpha opening: x209..640, y225..567
# on 850px original. Fit portrait as a centered 0.40 circle at y~0.465,
# keeping faces away from the top jewel and pendant without stretching.
a=s.index("class DedaFramedAvatar extends StatelessWidget {")
b=s.index("class _DedaLuxuryFramePainter",a)
oldFrame=s[a:b]
frame=exactly(oldFrame,
 "  @override\n  Widget build(BuildContext context) {",
 """  // DEDA_100344_OWNER_EXACT_ROYAL_FRAMES_PREVIEW_ONLY
  static const List<String> royalFrameAssets = <String>[
    'assets/deda_royal_frames/deda_frame_gold_royal.webp',
    'assets/deda_royal_frames/deda_frame_ruby_royal.webp',
    'assets/deda_royal_frames/deda_frame_emerald_royal.webp',
  ];

  @override
  Widget build(BuildContext context) {""",
 "frame static original assets")
frame=exactly(frame,
 "    final safeStyle = frameStyle.clamp(0, 5).toInt();",
 "    final safeStyle = frameStyle.clamp(0, 5).toInt();\n    final royalFrame = safeStyle >= 3;",
 "royal frame selector")
frame=exactly(frame,
 """          Container(
            width: size * 0.54,
            height: size * 0.54,""",
 """          Transform.translate(
            offset: Offset(0, royalFrame ? -size * 0.035 : 0),
            child: Container(
              width: size * (royalFrame ? 0.40 : 0.54),
              height: size * (royalFrame ? 0.40 : 0.54),""",
 "royal inner aperture geometry")
frame=exactly(frame,
 """                size: size * 0.52,""",
 """                size: size * (royalFrame ? 0.39 : 0.52),""",
 "royal face diameter")
frame=exactly(frame,
 """          ),
          Positioned.fill(
            child: IgnorePointer(""",
 """            ),
          ),
          Positioned.fill(
            child: IgnorePointer(""",
 "closing face transform")
frame=exactly(frame,
 """                'assets/deda_style/frame_$safeStyle.png',""",
 """                royalFrame
                    ? royalFrameAssets[safeStyle - 3]
                    : 'assets/deda_style/frame_$safeStyle.png',""",
 "original frame path")
assert "royalFrameAssets[safeStyle - 3]" in frame
assert frame.count("Transform.translate(")==1
s=s[:a]+frame+s[b:]

# Unlike 100340, do NOT veil a locked frame with a white overlay. Keep
# the owner original visible completely and show only a small lock icon.
a=s.index("class DedaProfileFramePreview extends StatelessWidget {")
b=s.index("class DedaPreferences {",a)
oldTile=s[a:b]
fromNeedle="          if (!free)\n            Positioned.fill("
endNeedle="\n        ],\n      ),"
assert oldTile.count(fromNeedle)==1
p=oldTile.index(fromNeedle)
q=oldTile.index(endNeedle,p)
tileLock="""          if (!free)
            PositionedDirectional(
              top: 5,
              end: 5,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xE71A254B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD880)),
                ),
                child: const Icon(Icons.lock_rounded,
                  color: Color(0xFFFFD880), size: 15),
              ),
            ),"""
tile=oldTile[:p]+tileLock+oldTile[q:]
assert "if (!free)" in tile and "Colors.white.withOpacity(0.52)" not in tile
s=s[:a]+tile+s[b:]

# The gentle flashes are painted ONLY on the selected fixed preview.
# Thumbnails are static, so offscreen grid items have no active tickers.
sparkle=r'''
class DedaRoyalFrameSparkle extends StatefulWidget {
  final double size;
  final int style;
  const DedaRoyalFrameSparkle({super.key, required this.size, required this.style});

  @override
  State<DedaRoyalFrameSparkle> createState() => _DedaRoyalFrameSparkleState();
}

class _DedaRoyalFrameSparkleState extends State<DedaRoyalFrameSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3300))..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accents = <Color>[
      Color(0xFFFFE7A9), Color(0xFFFFB4C8), Color(0xFFB5FFDD)
    ];
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) => CustomPaint(
              painter: _DedaRoyalFrameStars(
                t: _animation.value,
                color: accents[(widget.style - 3).clamp(0, 2).toInt()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DedaRoyalFrameStars extends CustomPainter {
  final double t;
  final Color color;
  const _DedaRoyalFrameStars({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const jewels = <Offset>[
      Offset(0.50, 0.14), Offset(0.24, 0.31), Offset(0.77, 0.31),
      Offset(0.18, 0.55), Offset(0.82, 0.55), Offset(0.50, 0.69),
      Offset(0.50, 0.89),
    ];
    for (var i=0; i<jewels.length; i++) {
      final pulse = (math.sin((t * 6.2831853) + i * 1.15) + 1.0) * 0.5;
      final opacity = (0.14 + 0.78 * pulse).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = size.width * (0.008 + 0.006 * pulse)
        ..strokeCap = StrokeCap.round;
      final center = Offset(jewels[i].dx * size.width, jewels[i].dy * size.height);
      final ray = size.width * (0.013 + 0.024 * pulse);
      canvas.drawLine(center.translate(-ray,0),center.translate(ray,0),paint);
      canvas.drawLine(center.translate(0,-ray),center.translate(0,ray),paint);
      canvas.drawCircle(center, size.width * 0.009, Paint()..color=Colors.white.withOpacity(opacity));
    }
  }

  @override
  bool shouldRepaint(covariant _DedaRoyalFrameStars old) =>
      old.t != t || old.color != color;
}

'''
anchor="class _DedaLuxuryFramePainter extends CustomPainter {"
s=exactly(s,anchor,sparkle+anchor,"royal shimmer class")

# Only modify the edit screen; the profile hero and all persisted legacy
# frames remain unchanged. Locked trials never update _frameStyle.
a=s.index("class _DedaEditProfilePageState extends State<DedaEditProfilePage> {")
b=s.index("class DedaAccountInfoPage extends StatefulWidget {",a)
oldEdit=s[a:b]
edit=exactly(oldEdit,
 "  late int _frameStyle;",
 "  late int _frameStyle;\n  int? _previewLockedFrame;",
 "temporary locked frame state")
previewStart=edit.index("deda_sticky_preview_avatar_card")
deda=edit.index("child: DedaFramedAvatar(",previewStart)
prefix=edit[:deda]
tail=edit[deda:]
snippet="""child: DedaFramedAvatar(
                  avatarStyle: _avatarStyle,
                  frameStyle: _frameStyle,
                  size: 126,
                ),"""
assert tail.count(snippet)==1, "SAFE_STOP preview widget moved"
replacement="""child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    DedaFramedAvatar(
                      avatarStyle: _avatarStyle,
                      frameStyle: _previewLockedFrame ?? _frameStyle,
                      size: 126,
                    ),
                    if (_previewLockedFrame != null)
                      DedaRoyalFrameSparkle(
                        size: 126, style: _previewLockedFrame!),
                    if (_previewLockedFrame != null)
                      Positioned(
                        bottom: 2,
                        left: 0,
                        child: Container(
                          key: const Key('deda_royal_frame_preview_only_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xEB17234C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dedaText('معاينة فقط', 'Preview only'),
                            style: const TextStyle(color: Color(0xFFFFE2A0),
                              fontSize: 9, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                  ],
                ),"""
tail=tail.replace(snippet,replacement,1)
edit=prefix+tail
edit=exactly(edit,
 """                    return InkWell(
                      onTap: free
                          ? () => setState(() => _frameStyle = index)
                          : _lockedFrameMessage,""",
 """                    return InkWell(
                      key: Key('deda_royal_frame_tile_$index'),
                      onTap: () => setState(() {
                        if (free) {
                          _frameStyle = index;
                          _previewLockedFrame = null;
                        } else {
                          _previewLockedFrame = index; // preview, NEVER purchase
                        }
                      }),""",
 "locked preview tap, no write")
edit=exactly(edit,
 """                                  : dedaText('مقفول', 'Locked'),""",
 """                                  : index == 3
                                      ? dedaText('ملكي ذهبي', 'Royal gold')
                                      : index == 4
                                          ? dedaText('ملكي ياقوتي', 'Royal ruby')
                                          : dedaText('ملكي زمردي', 'Royal emerald'),""",
 "three owner royal frame labels")
assert "await DedaPreferences.setProfileAppearance(" in edit
assert "frameStyle: _frameStyle," in edit, "SAFE_STOP saved frame altered"
assert "frameStyle: _previewLockedFrame" in edit
assert "DedaRoyalFrameSparkle(" in edit
assert "_previewLockedFrame = index" in edit
s=s[:a]+edit+s[b:]

# The Flutter manifest includes the exact three new WebP originals; the
# free png paths and royal portrait JPEGs stay as-is.
oldPub="    - assets/deda_home_bg.jpg\n"
assert pub.count(oldPub)==1
for name in expected:
 assert f"assets/deda_royal_frames/{name}" not in pub
pub=pub.replace(oldPub,oldPub+"".join(
    f"    - assets/deda_royal_frames/{name}\n" for name in expected
),1)
for key in ("class DedaDiamondsWallet {","class DedaSocialProgressWallet {","class DedaRoutePage extends StatefulWidget"):
 assert key in s
# Preserve exactly the real business logic outside the two presentation
# blocks and one shimmer renderer; no other Flutter sections touched.
assert "DEDA_100343_POINT7_ROYAL_INLINE_OWNED_IDS" in s
path.write_text(s,encoding="utf-8")
manifest.write_text(pub,encoding="utf-8")
print("PASS 100344: 3 exact owner 850px transparent WEBP frames, no substitutes")
print("PASS 100344: temporary locked preview + smooth sparkle, no purchase or saved selection mutation")
