import 'package:flutter/material.dart';

import 'deda_place_suggestions.dart';

/// One shared visual identity for the approved activity type.
/// Does not accept phone-gallery assets and never changes location/navigation.
class DedaPlaceActivitySymbol extends StatelessWidget {
  final String categoryCode;
  final String activityType;
  final String placeName;
  final IconData fallbackIcon;
  final Color color;
  final double size;

  const DedaPlaceActivitySymbol({
    super.key,
    required this.categoryCode,
    required this.activityType,
    required this.fallbackIcon,
    required this.color,
    required this.size,
    this.placeName = '',
  });

  @override
  Widget build(BuildContext context) {
    final emoji = DedaPlaceSuggestions.emojiForCategory(
      categoryCode,
      activityType,
      placeName: placeName,
    );
    if (emoji.isNotEmpty) {
      return ExcludeSemantics(
        child: Text(
          emoji,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size,
            height: 1,
          ),
        ),
      );
    }
    return Icon(fallbackIcon, size: size, color: color);
  }
}
