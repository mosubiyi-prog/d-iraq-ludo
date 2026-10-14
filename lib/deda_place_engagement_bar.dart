import 'package:flutter/material.dart';

/// DEDA 100332 follow/like strip shown only when a registered place is selected.
/// UI-only: the parent chooses visibility and handles server-confirmed actions.
class DedaPlaceEngagementBar extends StatelessWidget {
  final bool following;
  final bool liked;
  final int followers;
  final int likes;
  final bool busy;
  final bool loadingCount;
  final VoidCallback onFollow;
  final VoidCallback onLike;

  const DedaPlaceEngagementBar({
    super.key,
    required this.following,
    required this.liked,
    required this.followers,
    this.likes = 0,
    required this.busy,
    this.loadingCount = false,
    required this.onFollow,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              color: following
                  ? const Color(0xFF1877D2)
                  : const Color(0xFF9099A3),
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
            message: 'عدد الإعجابات الحقيقي',
            child: SizedBox(
              width: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  loadingCount ? '…' : '$likes',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFFE53935),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: 'عدد متابعي المكان',
              child: Row(
                children: [
                  const Icon(
                    Icons.people_alt_outlined,
                    size: 15,
                    color: Color(0xFFB8860B),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        loadingCount ? '…' : '$followers',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Color(0xFFB8860B),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
