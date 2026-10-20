import 'package:flutter/material.dart';

/// Shared *text ink* for DEDA identifiers. This does not buy, own, or grant
/// anything, and intentionally stores no identity or wallet state.
class DedaVerifiedIdentifierInk {
  DedaVerifiedIdentifierInk._();

  static final RegExp _identifier = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  /// A real color is applied only after an authenticated server read has
  /// confirmed the identifier and its permanently assigned cosmetic color.
  /// A user's local preview choice must never be passed as [permanentColor].
  static Color? resolve({
    required String identifier,
    required bool serverConfirmed,
    required String? permanentColor,
  }) {
    if (!serverConfirmed || !_identifier.hasMatch(identifier)) return null;
    switch (permanentColor) {
      case 'gold':
        return const Color(0xFFF2C463);
      case 'diamond':
        return const Color(0xFF87CEF7);
      case 'royal':
        return const Color(0xFFCE9AFF);
      case 'pink':
        return const Color(0xFFE96DAA);
      default:
        return null;
    }
  }
}

/// Ink affects the glyphs of @DEDA-ID themselves, never just their card.
/// Integrate with a verified *active* ID for public/profile/share surfaces,
/// and a verified *owned* ID for the general-manager grant history.
/// Caller must fetch ownership and color from an authenticated backend;
/// [serverConfirmed] is never proof of entitlement by itself.
class DedaVerifiedIdentifierText extends StatelessWidget {
  final String identifier;
  final bool serverConfirmed;
  final String? permanentColor;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const DedaVerifiedIdentifierText({
    super.key,
    required this.identifier,
    required this.serverConfirmed,
    required this.permanentColor,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final ink = DedaVerifiedIdentifierInk.resolve(
      identifier: identifier,
      serverConfirmed: serverConfirmed,
      permanentColor: permanentColor,
    );
    final inherited = DefaultTextStyle.of(context).style;
    final effective = inherited.merge(style).copyWith(
      color: ink ?? style?.color ?? inherited.color,
      shadows: ink == null
          ? style?.shadows ?? inherited.shadows
          : <Shadow>[
              Shadow(color: ink.withOpacity(0.30), blurRadius: 3),
            ],
    );
    return Text(
      identifier,
      textDirection: TextDirection.ltr,
      style: effective,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
