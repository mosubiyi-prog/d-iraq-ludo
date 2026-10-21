import 'package:flutter/material.dart';

import 'deda_lab_verified_frame_catalog.dart';

/// Real DEDA LAB original WebP art. The portrait uses each artist's measured
/// transparent aperture, never forces a generic 850px crop on all 16 designs.
class DedaLabOriginalFrameArtwork extends StatefulWidget {
  final DedaLabFrameSpec frame;
  final Widget Function(double) portrait;
  final double size;
  final bool animate;
  const DedaLabOriginalFrameArtwork({
    super.key, required this.frame, required this.portrait,
    required this.size, this.animate = true,
  });

  @override
  State<DedaLabOriginalFrameArtwork> createState() =>
      _DedaLabOriginalFrameArtworkState();
}

class _DedaLabOriginalFrameArtworkState
    extends State<DedaLabOriginalFrameArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5700),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || !widget.animate) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant DedaLabOriginalFrameArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      if (widget.animate && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        _shine.repeat();
      } else {
        _shine.stop();
      }
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final s = widget.size;
    final l = f.portraitLeft * s;
    final t = f.portraitTop * s;
    final w = f.portraitWidth * s;
    final h = f.portraitHeight * s;
    return SizedBox.square(
      dimension: s,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: l, top: t, width: w, height: h,
            child: ClipOval(
              child: SizedBox(width: w, height: h,
                child: FittedBox(fit: BoxFit.cover,
                  child: widget.portrait(w > h ? w : h))),
            ),
          ),
          Positioned.fill(child: Image.asset(f.assetPath, fit: BoxFit.contain,
            filterQuality: FilterQuality.high)),
          // The shimmer masks the artwork's alpha; no light band crosses
          // a transparent portrait aperture or covers the user's face.
          if (widget.animate)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shine,
                builder: (context, child) => Opacity(
                  opacity: 0.21,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) {
                      final center = _shine.value * 2.0 - 0.5;
                      return LinearGradient(
                        begin: Alignment(center * 2 - 1.7, -1),
                        end: Alignment(center * 2 + 0.3, 1),
                        colors: const [
                          Colors.transparent,
                          Color(0xFFF8F9D5),
                          Colors.transparent,
                        ],
                        stops: const [0.1, 0.48, 0.88],
                      ).createShader(bounds);
                    },
                    child: child!,
                  ),
                ),
                child: Image.asset(f.assetPath, fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinned original profile card belongs to parent edit-profile screen.
/// Only this list scrolls. 13 paid frames are previews ONLY until an
/// atomic, account-verified debit+ownership receipt really exists.
class DedaLabOriginalFrameGallery extends StatelessWidget {
  final int avatarStyle;
  final String? selectedId;
  final void Function(DedaLabFrameSpec) onSelect;
  final Widget Function(double) portrait;
  const DedaLabOriginalFrameGallery({
    super.key, required this.avatarStyle, required this.portrait,
    required this.onSelect, this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('deda_lab_original_16_gallery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Text('إطارات DEDA الأصلية · 16 إطاراً',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 17,fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('3 ملكية مجانية · 13 للمعاينة قبل الشراء · كل واحد 1000 ماسة',
          textAlign: TextAlign.right,
          style: TextStyle(color: Color(0xFF605F58),fontSize: 12)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final cell = ((constraints.maxWidth - 20) / 3)
              .clamp(90.0, 129.0).toDouble();
          return Wrap(
            spacing: 10, runSpacing: 12,
            alignment: WrapAlignment.center,
            children: dedaLabVerifiedFrames.map((frame) {
              final chosen = selectedId == frame.id;
              return InkWell(
                key: ValueKey('deda_lab_${frame.id}_tile'),
                onTap: () => onSelect(frame),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: cell,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: chosen ? const Color(0xFFF5F1DD) : Colors.white,
                    border: Border.all(color: chosen
                      ? const Color(0xFFD7AA43)
                      : const Color(0xFFDDE1D7),width: chosen ? 2 : 1),
                  ),
                  child: Column(children: [
                    DedaLabOriginalFrameArtwork(
                      frame: frame,portrait: portrait,
                      size: cell-12,animate: false),
                    Text(frame.nameAr,
                      textAlign: TextAlign.center,maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(frame.free ? 'مجاني · استخدام' : '🔒 1000 💎',
                      key: ValueKey('deda_lab_${frame.id}_price'),
                      style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: frame.free ? const Color(0xFF17652F)
                                          : const Color(0xFF905319))),
                  ]),
                ),
              );
            }).toList(),
          );
        }),
        const SizedBox(height: 10),
        const Text('المعاينة مجانية. شراء الإطارات المقفولة لا يخصم ماسات حتى تكتمل حماية ملكية الحساب.',
          key: Key('deda_lab_purchase_protected_no_fake_checkout'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11,color: Color(0xFF725C39))),
      ],
    );
  }
}
