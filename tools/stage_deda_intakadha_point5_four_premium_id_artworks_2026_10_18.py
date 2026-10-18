#!/usr/bin/env python3
"""Stage5/16: add four decorative ID-card styles to rebuilt DEDA source ONLY.

Run AFTER 100356 rebuild, six backgrounds, and approved points 2-4.
This only declares reusable widgets; point6 wires profile, point7 manages
ownership, and later points set prices. No wallet/Firebase/publication changes.
"""
from pathlib import Path

MAIN = Path("lib/main.dart")
ANCHOR = "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {"
MARKER = "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18"
ARTWORK = r'''// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18
// Decorative source only: not an entitlement, purchase or active-ID change.
enum DedaPremiumIdCardColor { gold, diamond, royal, pink }

class _DedaIdFoil {
  final Color base;
  final Color light;
  final Color shadow;
  final Color plate;
  final Color plateLight;
  final Color trim;
  final Color ink;
  final Color gem;
  final String name;
  const _DedaIdFoil(
    this.base, this.light, this.shadow, this.plate, this.plateLight,
    this.trim, this.ink, this.gem, this.name,
  );
  static _DedaIdFoil from(DedaPremiumIdCardColor variant) {
    switch (variant) {
      case DedaPremiumIdCardColor.gold:
        return const _DedaIdFoil(
          Color(0xFF150D06), Color(0xFF6C431A), Color(0xFF1F1008),
          Color(0xFF15100B), Color(0xFF4C3017), Color(0xFFFFCB71),
          Color(0xFFFFECB7), Color(0xFFFFE190), 'ذهبي',
        );
      case DedaPremiumIdCardColor.diamond:
        return const _DedaIdFoil(
          Color(0xFF7797B7), Color(0xFFE9F6FF), Color(0xFF90ACC7),
          Color(0xFF192537), Color(0xFF465C76), Color(0xFFD5ECFF),
          Color(0xFFF5FAFF), Color(0xFFFFFFFF), 'ماسي',
        );
      case DedaPremiumIdCardColor.royal:
        return const _DedaIdFoil(
          Color(0xFF2C063D), Color(0xFF802AAC), Color(0xFF220831),
          Color(0xFF210A36), Color(0xFF542178), Color(0xFFF8C77F),
          Color(0xFFFFEBC6), Color(0xFFE1AAFF), 'ملكي',
        );
      case DedaPremiumIdCardColor.pink:
        return const _DedaIdFoil(
          Color(0xFFE9A2B6), Color(0xFFFFEDF0), Color(0xFFF2BECD),
          Color(0xFFFFEDF1), Color(0xFFEDB0C0), Color(0xFFD47B97),
          Color(0xFF812E4A), Color(0xFFFFEFF4), 'وردي',
        );
    }
  }
}

/// Responsive 50px royal nameplate, modeled on owner's 4-color ID reference.
/// Live [identifier] is kept separate from the painted crown/gems, so the
/// original account ID can appear without baking a sample ID into artwork.
/// Appearance only: buying, use and ownership belong to later approved stages.
class DedaPremiumIdCard extends StatelessWidget {
  final String identifier;
  final DedaPremiumIdCardColor color;
  final VoidCallback? onTap;
  final double height;
  const DedaPremiumIdCard({
    super.key,
    required this.identifier,
    required this.color,
    this.onTap,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final foil = _DedaIdFoil.from(color);
    return Semantics(
      label: 'بطاقة معرّف ' + foil.name + ': ' + identifier,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _DedaIdFoilPainter(foil),
              child: Padding(
                // Avoid painting over crown and the right jewel at 320px width.
                padding: const EdgeInsetsDirectional.only(start: 68, end: 31),
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        identifier,
                        textDirection: TextDirection.ltr,
                        softWrap: false,
                        maxLines: 1,
                        style: TextStyle(
                          color: foil.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.12,
                          shadows: <Shadow>[
                            Shadow(
                              color: foil.shadow.withOpacity(0.42),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DedaIdFoilPainter extends CustomPainter {
  final _DedaIdFoil foil;
  const _DedaIdFoilPainter(this.foil);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 40 || h <= 30) return;
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size, const Radius.circular(14),
    );
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[foil.base, foil.light, foil.shadow],
          stops: const <double>[0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );
    // Inner dark/frosted nameplate and double foil engraving.
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(9, 8, w - 18, h - 16), const Radius.circular(9),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[foil.plateLight, foil.plate, foil.plateLight],
        ).createShader(plate.outerRect),
    );
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..color = foil.trim;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5, 1.5, w - 3, h - 3),
        const Radius.circular(13),
      ),
      outer,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, w - 8, h - 8),
        const Radius.circular(11),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = foil.gem.withOpacity(0.62),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = foil.trim.withOpacity(0.9),
    );

    // Jewels and crown are actual scalable vector paths, not letter glyphs.
    _diamond(canvas, Offset(18, h / 2), 6);
    _diamond(canvas, Offset(w - 18, h / 2), 6);
    _crown(canvas, Offset(47, h / 2), 18);
    final starlight = Paint()
      ..color = foil.gem.withOpacity(0.90)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (final o in <Offset>[
      Offset(12, 7), Offset(w - 12, 7),
      Offset(12, h - 7), Offset(w - 12, h - 7),
    ]) {
      canvas.drawLine(o.translate(-2.7, 0), o.translate(2.7, 0), starlight);
      canvas.drawLine(o.translate(0, -2.7), o.translate(0, 2.7), starlight);
    }
    canvas.restore();
  }

  void _diamond(Canvas canvas, Offset origin, double radius) {
    Path path(double scale) => Path()
      ..moveTo(origin.dx, origin.dy - radius * scale)
      ..lineTo(origin.dx + radius * scale, origin.dy)
      ..lineTo(origin.dx, origin.dy + radius * scale)
      ..lineTo(origin.dx - radius * scale, origin.dy)
      ..close();
    canvas.drawPath(path(1), Paint()..color = foil.trim);
    canvas.drawPath(path(0.70), Paint()..color = foil.gem);
    canvas.drawLine(
      Offset(origin.dx, origin.dy - radius * 0.7),
      Offset(origin.dx, origin.dy + radius * 0.7),
      Paint()..color = foil.base.withOpacity(0.55)..strokeWidth = 0.7,
    );
  }

  void _crown(Canvas canvas, Offset center, double span) {
    final x = center.dx - span / 2;
    final y = center.dy - span / 2;
    final crown = Path()
      ..moveTo(x, y + span * 0.25)
      ..lineTo(x + span * 0.18, y + span * 0.55)
      ..lineTo(x + span * 0.33, y + span * 0.08)
      ..lineTo(x + span * 0.50, y + span * 0.47)
      ..lineTo(x + span * 0.70, y + span * 0.08)
      ..lineTo(x + span * 0.83, y + span * 0.55)
      ..lineTo(x + span, y + span * 0.25)
      ..lineTo(x + span * 0.87, y + span * 0.82)
      ..lineTo(x + span * 0.13, y + span * 0.82)
      ..close();
    canvas.drawPath(crown, Paint()..color = foil.trim);
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = foil.gem,
    );
    _diamond(canvas, Offset(center.dx, y + span * 0.57), 2.2);
    canvas.drawLine(
      Offset(x + span * 0.13, y + span * 0.91),
      Offset(x + span * 0.87, y + span * 0.91),
      Paint()..color = foil.gem..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _DedaIdFoilPainter oldDelegate) {
    return oldDelegate.foil != foil;
  }
}

'''

def apply(source: str) -> str:
    if source.count(ANCHOR) != 1:
        raise ValueError("SAFE_STOP: missing or duplicate profile source anchor")
    if MARKER in source:
        if source.count(MARKER) != 1 or ARTWORK not in source:
            raise ValueError("SAFE_STOP: malformed or partial point5 stage")
        return source
    if "enum DedaPremiumIdCardColor" in source or "class DedaPremiumIdCard extends" in source:
        raise ValueError("SAFE_STOP: conflicting premium ID card type")
    for token in (
        "  Widget _profileHeroCard() {",
        "DedaStyleInventory",
        "DedaRoyalBackgroundArtwork",
        "// DEDA_INTAKADHA_POINT2_MEMBER_CAPTION_REMOVED_2026_10_18",
        "// DEDA_INTAKADHA_POINT3_TIGHT_HERO_LEVEL_LAYOUT_2026_10_18",
        "// DEDA_INTAKADHA_POINT4_RECTANGULAR_ID_50PX_2026_10_18",
    ):
        if token not in source:
            raise ValueError("SAFE_STOP: protected prerequisite absent: " + token)
    result = source.replace(ANCHOR, ARTWORK + ANCHOR, 1)
    if result.replace(ARTWORK, "", 1) != source:
        raise ValueError("SAFE_STOP: unrelated application source modified")
    return result

if __name__ == "__main__":
    if not MAIN.is_file():
        raise SystemExit("SAFE_STOP: regenerated lib/main.dart missing")
    old = MAIN.read_text(encoding="utf-8")
    try:
        new = apply(old)
    except ValueError as exc:
        raise SystemExit(str(exc))
    if new != old:
        MAIN.write_text(new, encoding="utf-8")
        print("PASS: four dynamic-ID card painter styles added, no hard-coded account ID")
    else:
        print("PASS: point5 already staged; unchanged")
    print("PASS: appearance only; ID purchases, profile use, Firebase and Play untouched")
