import 'package:flutter/material.dart';

/// DEDA 100332 follow/like strip shown only when a registered place is selected.
/// UI-only: the parent chooses visibility and handles server-confirmed actions.
class DedaPlaceEngagementBar extends StatelessWidget {
  final bool following;
  final bool liked;
  final int followers;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback onLike;

  const DedaPlaceEngagementBar({
    super.key,
    required this.following,
    required this.liked,
    required this.followers,
    required this.busy,
    required this.onFollow,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border.all(color: const Color(0xFFDAE5DD)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(blurRadius: 4, color: Color(0x20000000)),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            padding: EdgeInsets.zero,
            iconSize: 20,
            tooltip: following ? 'إلغاء متابعة المكان' : 'متابعة المكان',
            onPressed: busy ? null : onFollow,
            icon: Icon(
              following
                  ? Icons.how_to_reg_rounded
                  : Icons.person_add_alt_1_rounded,
              color: const Color(0xFF118452),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
            padding: EdgeInsets.zero,
            iconSize: 20,
            tooltip: liked ? 'إلغاء الإعجاب' : 'إعجاب',
            onPressed: busy ? null : onLike,
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              // DEDA approval: red filled heart after a successful like.
              color: liked
                  ? const Color(0xFFE53935)
                  : const Color(0xFF7F8A84),
            ),
          ),
          Tooltip(
            message: 'عدد متابعي المكان',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                  size: 15,
                  color: Color(0xFF5C6760),
                ),
                const SizedBox(width: 2),
                Text(
                  '$followers',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    color: Color(0xFF4F5953),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
