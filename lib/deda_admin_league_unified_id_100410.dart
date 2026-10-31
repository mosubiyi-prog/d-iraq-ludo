import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'deda_unified_active_id_100410.dart';

/// Backward-compatible manager widget. No independent Firebase lookup,
/// stream or premium-ID resolver: the same shared identity source as profile.
class DedaAdminLeagueActiveId extends StatelessWidget {
  const DedaAdminLeagueActiveId({super.key,required this.originalId,this.style});
  final String originalId;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    // Old pure widget fixtures initialize no Firebase, preserving their
    // original-id test labels without permitting such fallback in real app.
    if(Firebase.apps.isEmpty) return Text(originalId,
        textDirection:TextDirection.ltr,style:style??const TextStyle(fontSize:11));
    return DedaUnifiedActiveIdLabel100410(
        originalId:originalId,style:style);
  }
}
