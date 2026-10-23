import 'package:flutter/material.dart';
import 'deda_qa32_active_account_scope.dart';

/// Resolves only verified owner identity; canonical ID remains the fallback
/// and stable backend route. No local alias cache or hardcoded owner name.
class DedaSixActiveIdentity extends StatelessWidget {
  const DedaSixActiveIdentity({super.key, required this.originalId,
    this.style, this.selectable = false, this.textAlign = TextAlign.center});
  final String originalId;
  final TextStyle? style;
  final bool selectable;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => DedaQa32ActiveAccountScope(
    originalId: originalId,
    builder: (context, proof) {
      final id = proof?.displayId ?? originalId;
      return Directionality(textDirection: TextDirection.ltr,
        child: selectable ? SelectableText(id, style: style, textAlign: textAlign)
          : Text(id, style: style, textAlign: textAlign));
    });
}
