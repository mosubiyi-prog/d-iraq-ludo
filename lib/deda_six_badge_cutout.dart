import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'deda_100377_level_achievement_badges_policy.dart';
import 'deda_100377_level_achievements_page_staged.dart';

/// Render the approved ORIGINAL RGB sheet inside a display silhouette.
/// The generated cutout supplies alpha only; its RGB is never displayed.
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
    try { return (await codec.getNextFrame()).image; }
    finally { codec.dispose(); }
  }
  static _BadgeAssets? _ready;
  static Future<_BadgeAssets> _load() async {
    final art=await _decode(DedaOriginalSixLevelBadgeArt.asset);
    final mask=await _decode(maskAsset);
    try {
      final bytes=(await mask.toByteData(format:ui.ImageByteFormat.rawRgba))!;
      final w=mask.width~/3, h=mask.height~/2;
      final paths=<Path>[];
      for(var cell=0;cell<6;cell++) {
        final path=Path();
        final ox=(cell%3)*w, oy=(cell~/3)*h;
        // Compile the alpha boundary once into a clip path. No color filter
        // or alpha multiplication can remove the original dark interior.
        for(var y=0;y<h;y++) {
          var x=0;
          while(x<w) {
            bool solid(int at) => bytes.getUint8(((oy+y)*mask.width+ox+at)*4+3)>=128;
            while(x<w && !solid(x)) {x++;}
            final start=x;
            while(x<w && solid(x)) {x++;}
            if(x>start) path.addRect(Rect.fromLTWH(
                start/w,y/h,(x-start)/w,1/h));
          }
        }
        paths.add(path);
      }
      return _ready = _BadgeAssets(art,paths);
    } finally {mask.dispose();}
  }
  static final Future<_BadgeAssets> _assets=_load();
  static Future<void> warmUp() async {await _assets;}
  @override
  Widget build(BuildContext context) => SizedBox(
    key:ValueKey('deda_owner_level_art_${tier.id}'), width:size,height:size,
    child: _ready != null ? CustomPaint(painter:_BadgePainter(_ready!,tier))
      : FutureBuilder<_BadgeAssets>(future:_assets,builder:(context,snapshot) {
      if(snapshot.hasError) return const Icon(Icons.image_not_supported_outlined);
      final assets=snapshot.data;
      if(assets==null) return const SizedBox.shrink();
      return CustomPaint(painter:_BadgePainter(assets,tier));
    }));
}
class _BadgeAssets {
  const _BadgeAssets(this.art,this.paths);
  final ui.Image art;
  final List<Path> paths;
}
class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.assets,this.tier);
  final _BadgeAssets assets;
  final DedaLevelBadgeTier tier;
  int get cell => switch(tier) {
    DedaLevelBadgeTier.gold=>0,DedaLevelBadgeTier.silver=>1,
    DedaLevelBadgeTier.emerald=>2,DedaLevelBadgeTier.diamond=>3,
    DedaLevelBadgeTier.royal=>4,DedaLevelBadgeTier.legendary=>5,
  };
  @override
  void paint(Canvas canvas,Size size) {
    final art=assets.art;
    final src=Rect.fromLTWH((cell%3)*art.width/3,(cell~/3)*art.height/2,
        art.width/3,art.height/2);
    canvas.save();
    canvas.clipPath(assets.paths[cell].transform(
      Matrix4.diagonal3Values(size.width,size.height,1).storage));
    canvas.drawImageRect(art,src,Offset.zero & size,
      Paint()..filterQuality=FilterQuality.medium);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _BadgePainter old)=>
      old.assets!=assets || old.tier!=tier;
}
