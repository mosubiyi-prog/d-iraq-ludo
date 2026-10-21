import 'package:flutter/material.dart';
import 'deda_lab_verified_frame_catalog.dart';

/// LAB 16: existing three royals retain native styles 3,4,5.
/// 13 original premium assets use styles 6..18 (preview never purchases).
class DedaLabPremiumFrameStyles {
  static final List<DedaLabFrameSpec> paidFrames =
      dedaLabVerifiedFrames.where((f) => !f.free).toList(growable: false);
  static DedaLabFrameSpec? byProfileStyle(int style) =>
      style >= 6 && style < 6 + paidFrames.length
          ? paidFrames[style - 6] : null;
  static int? profileStyleOf(DedaLabFrameSpec spec) {
    if (spec.free) return null;
    final index = paidFrames.indexWhere((f) => f.id == spec.id);
    return index < 0 ? null : index + 6;
  }
}

/// Exact original transparent WebP frame, with its individually measured
/// central portrait hole. Animated jewelry only; no moving/warping face.
class DedaLabPremiumFrameArtwork extends StatefulWidget {
  final DedaLabFrameSpec spec;
  final double size;
  final Widget portrait;
  final bool animate;
  const DedaLabPremiumFrameArtwork({
    super.key, required this.spec, required this.size,
    required this.portrait, this.animate = true,
  });
  @override
  State<DedaLabPremiumFrameArtwork> createState() =>
      _DedaLabPremiumFrameArtworkState();
}
class _DedaLabPremiumFrameArtworkState
    extends State<DedaLabPremiumFrameArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 5400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant DedaLabPremiumFrameArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldRun = widget.animate && widget.size >= 120 && !reduced;
    if (shouldRun && !_shine.isAnimating) {
      _shine.repeat();
    } else if (!shouldRun && _shine.isAnimating) {
      _shine.stop();
    }
  }

  @override
  void dispose() { _shine.dispose(); super.dispose(); }

  Widget _image() => Image.asset(
    widget.spec.assetPath, fit: BoxFit.contain,
    filterQuality: FilterQuality.high, gaplessPlayback: true,
    errorBuilder: (context, error, stack) =>
      const Icon(Icons.broken_image_outlined, color: Color(0xFF8B294E)),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final d = widget.size;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion = widget.animate && d >= 120 && !reduced;

    final still = Stack(
      key: ValueKey<String>('deda_lab_original_' + s.id),
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: d*s.portraitLeft, top: d*s.portraitTop,
          width: d*s.portraitWidth, height: d*s.portraitHeight,
          child: ClipOval(
            child: FittedBox(
              fit: BoxFit.cover, clipBehavior: Clip.hardEdge,
              child: SizedBox.square(
                dimension: d*s.portraitWidth,
                child: widget.portrait,
              ),
            ),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: _image())),
      ],
    );
    return SizedBox.square(
      dimension: d,
      child: RepaintBoundary(
        child: !motion ? still : AnimatedBuilder(
          animation: _shine, child: still,
          builder: (context, image) {
            final position = _shine.value;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: image!),
              // Original WebP alpha limits shimmer to jeweled ornaments.
              Positioned.fill(child: IgnorePointer(child: Opacity(
                opacity: 0.34,
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment(-3.0+5.4*position,-0.8),
                    end: Alignment(-2.3+5.4*position,0.8),
                    colors: const [
                      Color(0x00FFFFFF), Color(0xDEFFF3C2),
                      Color(0x00FFFFFF)],
                    stops: const [0,0.5,1],
                  ).createShader(bounds),
                  child: _image(),
                ),
              ))),
            ]);
          },
        ),
      ),
    );
  }
}
