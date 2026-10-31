import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies only the *verified visible* ID. Never copies a canonical account
/// routing key on behalf of a user who has activated a premium public ID.
class DedaFriendIdCopy100411 extends StatelessWidget {
  const DedaFriendIdCopy100411({
    super.key,
    required this.verifiedDisplayId,
    required this.child,
  });

  final String? verifiedDisplayId;
  final Widget child;

  // Return exactly the ASCII identifier shown, not a normalized or bidi-
  // decorated UI representation. Reject commas, whitespace and direction marks.
  static String? exactCopyValue(String? value) {
    if (value == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{4,12}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final id = exactCopyValue(verifiedDisplayId);
    if (id == null) return child;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: InkWell(
            key: const Key('deda_friend_id_copy_tap'),
            onTap: () => _copy(context, id),
            child: child,
          ),
        ),
        const SizedBox(width: 3),
        IconButton(
          key: const Key('deda_friend_id_copy_icon'),
          tooltip: 'نسخ آيدي الصديق',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 29, minHeight: 29),
          icon: const Icon(Icons.copy_rounded, size: 16),
          onPressed: () => _copy(context, id),
        ),
      ],
    );
  }

  static Future<void> _copy(BuildContext context, String id) async {
    // No formatting, Arabic comma, LTR/RLM marks or space is put on clipboard.
    await Clipboard.setData(ClipboardData(text: id));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('تم نسخ آيدي الصديق')),
    );
  }
}
