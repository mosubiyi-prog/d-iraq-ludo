import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'deda_100377_level_achievement_badges_policy.dart';
import 'deda_100377_level_achievements_page_staged.dart';

/// Keep every visible color/detail from the approved ORIGINAL sheet.
/// The generated cutout supplies alpha only; its RGB is never rendered.
/// No change to the caller's badge size, position, tier or earned status.
class DedaSixBadgeCutout extends StatelessWidget {
  const DedaSixBadgeCutout({super.key, required this.tier, required this.size});
  final DedaLevelBadgeTier tier;
  final double size;
  static const maskAsset =
      'assets/deda_owner_level_badges/owner_six_rank_background_alpha_v1.png';

  static Future<ui.Image> _decode(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(
        data.offsetInBytes, data.lengthInBytes));
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  // Shared immutable app assets; never cached account data.
  static final Future<List<ui.Image>> _images = Future.wait([
    _decode(DedaOriginalSixLevelBadgeArt.asset), _decode(maskAsset),
  ]);
  static Future<void> warmUp() async { await _images; }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('deda_owner_level_art_${tier.id}'),
    width: size, height: size,
    child: FutureBuilder<List<ui.Image>>(
      future: _images,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Icon(Icons.image_not_supported_outlined);
        }
        final images = snapshot.data;
        if (images == null) return const SizedBox.shrink();
        return CustomPaint(painter: _BadgePainter(images[0], images[1], tier));
      },
    ),
  );
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.art, this.mask, this.tier);
  final ui.Image art;
  final ui.Image mask;
  final DedaLevelBadgeTier tier;
  static const _alphaOnly = ColorFilter.matrix([
    0, 0, 0, 0, 255,
    0, 0, 0, 0, 255,
    0, 0, 0, 0, 255,
    // Opaque silhouette retains the original art's interior dark colors.
    // Alpha below the silhouette threshold removes only exterior backdrop.
    0, 0, 0, 1000, -127000,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final column = switch (tier) {
      DedaLevelBadgeTier.gold || DedaLevelBadgeTier.diamond => 0,
      DedaLevelBadgeTier.silver || DedaLevelBadgeTier.royal => 1,
      _ => 2,
    };
    final row = switch (tier) {
      DedaLevelBadgeTier.gold || DedaLevelBadgeTier.silver ||
      DedaLevelBadgeTier.emerald => 0,
      _ => 1,
    };
    Rect cell(ui.Image image) => Rect.fromLTWH(
      column * image.width / 3, row * image.height / 2,
      image.width / 3, image.height / 2,
    );
    final destination = Offset.zero & size;
    canvas.saveLayer(destination, Paint());
    canvas.drawImageRect(art, cell(art), destination,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.drawImageRect(mask, cell(mask), destination,
        Paint()..filterQuality = FilterQuality.medium
          ..colorFilter = _alphaOnly ..blendMode = BlendMode.dstIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BadgePainter old) =>
      old.art != art || old.mask != mask || old.tier != tier;
}
