import 'package:flutter/material.dart';

/// DEDA manager dashboard tiles share the small 3-column footprint and
/// saturated category palette of the accepted main-home category tiles.
///
/// Visual change ONLY: supplied permissions, titles and onTap routes remain
/// owned by the administration page. Subtitle remains in Semantics even
/// when concealed on narrow phone tiles to preserve the home-card sizing.
class DedaAdminCompactCard extends StatelessWidget {
  const DedaAdminCompactCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accentColor = const Color(0xFF17652F),
    this.backgroundColor = const Color(0xDDF4F8F1),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final small = constraints.maxWidth < 138;
      final palette = HSLColor.fromColor(accentColor)
          .withSaturation(0.77)
          .withLightness(0.43);
      final vivid = palette.toColor();
      final bright = palette.withLightness(0.56).toColor();
      final dark = palette.withLightness(0.26).toColor();

      return Semantics(
        button: true,
        label: '$title. $subtitle',
        child: Card(
          elevation: 2.8,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: vivid,
          shadowColor: vivid.withOpacity(0.33),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xCCFFFFFF), width: 1.3),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bright, vivid, dark],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
            child: Stack(
              children: [
                PositionedDirectional(
                  top: -30,
                  start: -18,
                  child: Container(
                    width: small ? 79 : 100,
                    height: small ? 79 : 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: -26,
                  end: -32,
                  child: Container(
                    width: small ? 87 : 110,
                    height: small ? 87 : 110,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: small ? 4 : 8,
                          vertical: small ? 7 : 9,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: small ? 35 : 42,
                              height: small ? 35 : 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.19),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.62),
                                  width: 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(icon,
                                color: Colors.white,
                                size: small ? 22 : 26),
                            ),
                            SizedBox(height: small ? 7 : 9),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: small ? 12.1 : 14.5,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x55000000),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                            if (!small) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  height: 1.1,
                                  color: Color(0xFFEFF9FF),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
