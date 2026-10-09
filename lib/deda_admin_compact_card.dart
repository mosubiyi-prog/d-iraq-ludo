import 'package:flutter/material.dart';

/// One compact, responsive administration tile. Changes are visual ONLY;
/// permission checks, routes and callbacks stay with their existing caller.
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
      final compact = constraints.maxWidth < 154;
      final iconSize = compact ? 37.0 : 42.0;
      final titleSize = compact ? 12.5 : 13.5;
      final subtitleSize = compact ? 10.2 : 11.0;
      return Card(
        elevation: 1.5,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: BorderSide(color: accentColor.withOpacity(0.25)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(0.12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.8), width: 1.2),
                  ),
                  child: Icon(icon, size: iconSize * 0.55, color: accentColor),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  textDirection: Directionality.of(context),
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: titleSize,
                    height: 1.13, color: const Color(0xFF14271A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: subtitleSize, height: 1.17,
                    color: const Color(0xFF526155),
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
